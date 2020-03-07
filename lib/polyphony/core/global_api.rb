# frozen_string_literal: true

export_default :API

import '../extensions/core'
import '../extensions/fiber'

Exceptions  = import '../core/exceptions'
Throttler   = import '../core/throttler'

# Global API methods to be included in ::Object
module API
  def after(interval, &block)
    spin do
      sleep interval
      block.()
    end
  end

  def cancel_after(interval, &block)
    fiber = ::Fiber.current
    canceller = spin do
      sleep interval
      fiber.schedule Exceptions::Cancel.new
    end
    block.call
  ensure
    canceller.stop
  end

  def spin(tag = nil, &block)
    Fiber.current.spin(tag, caller, &block)
  end

  def spin_loop(tag = nil, rate: nil, &block)
    if rate
      Fiber.current.spin(tag, caller) do
        throttled_loop(rate, &block)
      end
    else
      Fiber.current.spin(tag, caller) { loop(&block) }
    end
  end

  def every(interval)
    timer = Gyro::Timer.new(interval, interval)
    loop do
      timer.await
      yield
    end
  ensure
    timer.stop
  end

  def move_on_after(interval, with_value: nil, &block)
    fiber = ::Fiber.current
    canceller = spin do
      sleep interval
      fiber.schedule Exceptions::MoveOn.new(with_value)
    end
    block.call
  rescue Exceptions::MoveOn => e
    e.value
  ensure
    canceller.stop
  end

  def receive
    Fiber.current.receive
  end

  def receive_pending
    Fiber.current.receive_pending
  end

  def supervise(*args, &block)
    Fiber.current.supervise(*args, &block)
  end

  def sleep(duration = nil)
    return sleep_forever unless duration

    timer = Gyro::Timer.new(duration, 0)
    timer.await
  end

  def sleep_forever
    Thread.current.fiber_ref
    suspend
  ensure
    Thread.current.fiber_unref
  end

  def throttled_loop(rate, count: nil, &block)
    throttler = Throttler.new(rate)
    if count
      count.times { throttler.(&block) }
    else
      loop { throttler.(&block) }
    end
  ensure
    throttler.stop
  end
end
