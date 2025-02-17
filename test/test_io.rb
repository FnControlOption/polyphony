# frozen_string_literal: true

require_relative 'helper'
require 'msgpack'

class IOTest < MiniTest::Test
  def setup
    super
    @i, @o = IO.pipe
  end

  def test_that_io_op_yields_to_other_fibers
    count = 0
    msg = nil
    [
      spin do
        @o.write('hello')
        @o.close
      end,

      spin do
        while count < 5
          sleep 0.01
          count += 1
        end
      end,

      spin { msg = @i.read }
    ].each(&:await)
    assert_equal 5, count
    assert_equal 'hello', msg
  end

  def test_write_multiple_arguments
    i, o = IO.pipe
    count = o.write('a', 'b', "\n", 'c')
    assert_equal 4, count
    o.close
    assert_equal "ab\nc", i.read
  end

  def test_that_double_chevron_method_returns_io
    assert_equal @o, @o << 'foo'

    @o << 'bar' << 'baz'
    @o.close
    assert_equal 'foobarbaz', @i.read
  end

  def test_wait_io
    results = []
    i, o = IO.pipe
    f = spin do
      loop do
        result = i.orig_read_nonblock(8192, exception: false)
        results << result
        case result
        when :wait_readable
          Thread.current.backend.wait_io(i, false)
        else
          break result
        end
      end
    end

    snooze
    o.write('foo')
    o.close

    result = f.await

    assert_equal 'foo', f.await
    assert_equal [:wait_readable, 'foo'], results
  end

  def test_read
    i, o = IO.pipe

    o << 'hi'
    assert_equal 'hi', i.read(2)

    o << 'foobarbaz'
    assert_equal 'foo', i.read(3)
    assert_equal 'bar', i.read(3)

    buf = +'abc'
    assert_equal 'baz', i.read(3, buf)
    assert_equal 'baz', buf

    buf = +'def'
    o << 'foobar'
    assert_equal 'deffoobar', i.read(6, buf, -1)
    assert_equal 'deffoobar', buf
  end

  def test_readpartial
    i, o = IO.pipe

    o << 'hi'
    assert_equal 'hi', i.readpartial(3)

    o << 'hi'
    assert_equal 'h', i.readpartial(1)
    assert_equal 'i', i.readpartial(1)

    spin {
      sleep 0.01
      o << 'hi'
    }
    assert_equal 'hi', i.readpartial(2)
    o.close

    assert_raises(EOFError) { i.readpartial(1) }
  end

  def test_gets
    i, o = IO.pipe

    buf = []
    f = spin do
      peer = receive
      while (l = i.gets)
        buf << l
        peer << true
      end
    end

    snooze
    assert_equal [], buf

    o << 'fab'
    f << Fiber.current
    sleep 0.05
    assert_equal [], buf

    o << "ulous\n"
    receive
    assert_equal ["fabulous\n"], buf

    o.close
    f.await
    assert_equal ["fabulous\n"], buf
  end

  def test_getc
    i, o = IO.pipe

    buf = []
    f = spin do
      while (c = i.getc)
        buf << c
      end
    end

    snooze
    assert_equal [], buf

    o << 'f'
    snooze
    o << 'g'
    o.close
    f.await
    assert_equal ['f', 'g'], buf
  end

  def test_getbyte
    i, o = IO.pipe

    buf = []
    f = spin do
      while (b = i.getbyte)
        buf << b
      end
    end

    snooze
    assert_equal [], buf

    o << 'f'
    snooze
    o << 'g'
    o.close
    f.await
    assert_equal [102, 103], buf
  end

  # see https://github.com/digital-fabric/polyphony/issues/30
  def test_reopened_tempfile
    file = Tempfile.new
    file << 'hello: world'
    file.close

    buf = nil
    File.open(file, 'r:bom|utf-8') do |f|
      buf = f.read(16384)
    end

    assert_equal 'hello: world', buf
  end

  def test_feed_loop_with_block
    i, o = IO.pipe
    unpacker = MessagePack::Unpacker.new
    buffer = []
    reader = spin do
      i.feed_loop(unpacker, :feed_each) { |msg| buffer << msg }
    end
    o << 'foo'.to_msgpack
    sleep 0.01
    assert_equal ['foo'], buffer

    o << 'bar'.to_msgpack
    sleep 0.01
    assert_equal ['foo', 'bar'], buffer

    o << 'baz'.to_msgpack
    sleep 0.01
    assert_equal ['foo', 'bar', 'baz'], buffer
  end

  class Receiver1
    attr_reader :buffer

    def initialize
      @buffer = []
    end

    def recv(obj)
      @buffer << obj
    end
  end

  def test_feed_loop_without_block
    i, o = IO.pipe
    receiver = Receiver1.new
    reader = spin do
      i.feed_loop(receiver, :recv)
    end
    o << 'foo'
    sleep 0.01
    assert_equal ['foo'], receiver.buffer

    o << 'bar'
    sleep 0.01
    assert_equal ['foo', 'bar'], receiver.buffer

    o << 'baz'
    sleep 0.01
    assert_equal ['foo', 'bar', 'baz'], receiver.buffer
  end

  class Receiver2
    attr_reader :buffer

    def initialize
      @buffer = []
    end

    def call(obj)
      @buffer << obj
    end
  end

  def test_feed_loop_without_method
    i, o = IO.pipe
    receiver = Receiver2.new
    reader = spin do
      i.feed_loop(receiver)
    end
    o << 'foo'
    sleep 0.01
    assert_equal ['foo'], receiver.buffer

    o << 'bar'
    sleep 0.01
    assert_equal ['foo', 'bar'], receiver.buffer

    o << 'baz'
    sleep 0.01
    assert_equal ['foo', 'bar', 'baz'], receiver.buffer
  end
end

class IOClassMethodsTest < MiniTest::Test
  def test_binread
    s = IO.binread(__FILE__)
    assert_kind_of String, s
    assert !s.empty?
    assert_equal IO.orig_binread(__FILE__), s

    s = IO.binread(__FILE__, 100)
    assert_equal 100, s.bytesize
    assert_equal IO.orig_binread(__FILE__, 100), s

    s = IO.binread(__FILE__, 100, 2)
    assert_equal 100, s.bytesize
    assert_equal 'frozen', s[0..5]
  end

  BIN_DATA = "\x00\x01\x02\x03"

  def test_binwrite
    fn = '/tmp/test_binwrite'
    FileUtils.rm(fn) rescue nil

    len = IO.binwrite(fn, BIN_DATA)
    assert_equal 4, len
    s = IO.binread(fn)
    assert_equal BIN_DATA, s
  end

  def test_foreach
    skip 'IO.foreach is not yet implemented'
    lines = []
    IO.foreach(__FILE__) { |l| lines << l }
    assert_equal "# frozen_string_literal: true\n", lines[0]
    assert_equal "end\n", lines[-1]
  end

  def test_read_class_method
    s = IO.read(__FILE__)
    assert_kind_of String, s
    assert(!s.empty?)
    assert_equal IO.orig_read(__FILE__), s

    s = IO.read(__FILE__, 100)
    assert_equal 100, s.bytesize
    assert_equal IO.orig_read(__FILE__, 100), s

    s = IO.read(__FILE__, 100, 2)
    assert_equal 100, s.bytesize
    assert_equal 'frozen', s[0..5]
  end

  def test_readlines
    lines = IO.readlines(__FILE__)
    assert_equal "# frozen_string_literal: true\n", lines[0]
    assert_equal "end\n", lines[-1]
  end

  WRITE_DATA = "foo\nbar קוקו"

  def test_write_class_method
    fn = '/tmp/test_write'
    FileUtils.rm(fn) rescue nil

    len = IO.write(fn, WRITE_DATA)
    assert_equal WRITE_DATA.bytesize, len
    s = IO.read(fn)
    assert_equal WRITE_DATA, s
  end

  def test_popen
    skip unless IS_LINUX

    counter = 0
    timer = spin { throttled_loop(200) { counter += 1 } }

    IO.popen('sleep 0.05') { |io| io.read(8192) }
    assert(counter >= 5)

    result = nil
    IO.popen('echo "foo"') { |io| result = io.read(8192) }
    assert_equal "foo\n", result
  ensure
    timer&.stop
  end

  def test_kernel_gets
    counter = 0
    timer = spin { throttled_loop(200) { counter += 1 } }

    i, o = IO.pipe
    orig_stdin = $stdin
    $stdin = i
    spin do
      sleep 0.01
      o.puts 'foo'
      o.close
    end

    assert(counter >= 0)
    assert_equal "foo\n", gets
  ensure
    $stdin = orig_stdin
    timer&.stop
  end

  def test_kernel_gets_with_argv
    ARGV << __FILE__

    s = StringIO.new(IO.orig_read(__FILE__))

    while (l = s.gets)
      assert_equal l, gets
    end
  ensure
    ARGV.delete __FILE__
  end

  def test_kernel_puts
    orig_stdout = $stdout
    o = eg(
      '@buf': +'',
      write:  ->(*args) { args.each { |a| @buf << a } },
      flush:  -> {},
      buf:    -> { @buf }
    )

    $stdout = o

    puts 'foobar'
    assert_equal "foobar\n", o.buf
  ensure
    $stdout = orig_stdout
  end

  def test_read_large_file
    fn = '/tmp/test.txt'
    File.open(fn, 'w') { |f| f << ('*' * 1e6) }
    s = IO.read(fn)
    assert_equal 1e6, s.bytesize
    assert s == IO.orig_read(fn)
  end

  def pipe_read
    i, o = IO.pipe
    yield o
    o.close
    i.read
  ensure
    i.close
  end

  def test_puts
    assert_equal "foo\n", pipe_read { |f| f.puts 'foo' }
    assert_equal "foo\n", pipe_read { |f| f.puts "foo\n" }
    assert_equal "foo\nbar\n", pipe_read { |f| f.puts 'foo', 'bar' }
    assert_equal "foo\nbar\n", pipe_read { |f| f.puts 'foo', "bar\n" }
  end

  def test_read_loop
    i, o = IO.pipe

    buf = []
    f = spin do
      buf << :ready
      i.read_loop { |d| buf << d }
      buf << :done
    end

    # writing always causes snoozing
    o << 'foo'
    o << 'bar'
    o.close

    f.await
    assert_equal [:ready, 'foo', 'bar', :done], buf
  end

  def test_read_loop_with_max_len
    r, w = IO.pipe

    w << 'foobar'
    w.close
    buf = []
    r.read_loop(3) { |data| buf << data }
    assert_equal ['foo', 'bar'], buf
  end
end
