# frozen_string_literal: true

require_relative 'helper'

class SuperviseTest < MiniTest::Test
  def test_supervise_with_no_arguments
    assert_raises(RuntimeError) do
      supervise
    end
  end
  
  def test_supervise_with_block
    buffer = []
    f1 = spin(:f1) { receive }
    f2 = spin(:f2) { receive }
    supervisor = spin(:supervisor) { supervise(f1, f2) { |*args| buffer << args } }

    snooze
    f1 << 'foo'
    f1.await
    10.times { snooze }
    assert_equal [[f1, 'foo']], buffer

    f2 << 'bar'
    f2.await
    assert_equal [[f1, 'foo'], [f2, 'bar']], buffer
  end

#   def test_supervise_with_restart
#     watcher = spin { receive }
#     parent = spin { supervise(restart: true, watcher: watcher) }
#     snooze

#     buffer = []
#     f1 = parent.spin do
#       buffer << 'f1'
#     end

#     f1.await
#     assert_equal ['f1'], buffer
#     watcher.await
#     assert_equal ['f1', 'f1'], buffer
#   end

#   def test_supervise_with_restart_on_error
#     parent = spin { supervise(restart: true) }
#     snooze

#     buffer = []
#     f1 = parent.spin do
#       buffer << 'f1'
#       buffer << receive
#     end

#     snooze
#     assert_equal ['f1'], buffer

#     f1.raise 'foo'

#     3.times { snooze }

#     assert_equal ['f1', 'f1'], buffer
#     assert_equal :dead, f1.state

#     # f1 should have been restarted by supervisor
#     f1 = parent.children.first
#     assert_kind_of Fiber, f1

#     f1 << 'foo'
#     f1.await

#     assert_equal ['f1', 'f1', 'foo'], buffer
#   end

#   def test_supervisor_termination
#     f = nil
#     p = spin do
#       f = spin { sleep 1 }
#       supervise
#     end
#     sleep 0.01

#     p.terminate
#     p.await

#     assert :dead, f.state
#     assert :dead, p.state
#   end

#   def test_supervisor_termination_with_restart
#     f = nil
#     p = spin do
#       f = spin { sleep 1 }
#       supervise(restart: true)
#     end
#     sleep 0.01

#     p.terminate
#     p.await

#     assert :dead, f.state
#     assert :dead, p.state
#   end
end
