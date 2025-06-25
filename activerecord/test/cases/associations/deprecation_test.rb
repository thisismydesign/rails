# frozen_string_literal: true

require "cases/helper"
require "models/dats"

# The logic of the `guard` method is extensively tested indirectly, via the test
# suites of each type of association.
#
# Those tests verify that the `report` method is invoked as expected. Here, we
# unit test the `report` method itself.
module AssociationDeprecationTest
  class ModeWriterTest < ActiveRecord::TestCase
    def setup
      @original_mode = ActiveRecord::Associations::Deprecation.mode
    end

    def teardown
      ActiveRecord::Associations::Deprecation.mode = @original_mode
    end

    test "valid values" do
      [:warn, :raise, :notify].each do |mode|
        ActiveRecord::Associations::Deprecation.mode = mode
        assert_equal mode, ActiveRecord::Associations::Deprecation.mode
      end
    end

    test "invalid values" do
      error = assert_raises(ArgumentError) do
        ActiveRecord::Associations::Deprecation.mode = :invalid
      end

      assert_equal "Invalid deprecated associations mode :invalid. Valid modes are :warn, :raise, and :notify.", error.message
    end
  end

  class WarnModeTest < ActiveRecord::TestCase
    def setup
      @original_logger = ActiveRecord::Base.logger
      @io = StringIO.new
      ActiveRecord::Base.logger = Logger.new(@io)

      @original_mode = ActiveRecord::Associations::Deprecation.mode
      ActiveRecord::Associations::Deprecation.mode = :warn
    end

    def teardown
      ActiveRecord::Base.logger = @original_logger
      ActiveRecord::Associations::Deprecation.mode = @original_mode
    end

    test "report warns in :warn mode" do
      DATS::Car.new.deprecated_tyres
      assert_match(/The association DATS::Car#deprecated_tyres is deprecated, the method deprecated_tyres was invoked (.+)\Z/, @io.string)
    end
  end

  class WarnModeNoLoggerTest < ActiveRecord::TestCase
    def setup
      @original_mode = ActiveRecord::Associations::Deprecation.mode
      ActiveRecord::Associations::Deprecation.mode = :warn

      @original_logger = ActiveRecord::Base.logger
      ActiveRecord::Base.logger = nil
    end

    def teardown
      ActiveRecord::Associations::Deprecation.mode = @original_mode
      ActiveRecord::Base.logger = @original_logger
    end

    test "report does not blow up in :warn mode if the logger is nil" do
      messages = []

      ActiveRecord::Base.logger.stub(:warn, ->(message) { messages << message }) do
        DATS::Car.new.deprecated_tyres
      end

      assert_empty messages, "Expected no warning to be issued when the logger is nil"
    end
  end

  class NotifyModeTest < ActiveRecord::TestCase
    def setup
      @original_mode = ActiveRecord::Associations::Deprecation.mode
      ActiveRecord::Associations::Deprecation.mode = :notify

      @original_backtrace_cleaner = ActiveRecord::LogSubscriber.backtrace_cleaner
      ActiveRecord::LogSubscriber.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new
      ActiveRecord::LogSubscriber.backtrace_cleaner.add_silencer { !_1.include?("_test.rb") }
    end

    def teardown
      ActiveRecord::Associations::Deprecation.mode = @original_mode
      ActiveRecord::LogSubscriber.backtrace_cleaner = @original_backtrace_cleaner
    end

    test "report publishes an Active Support notification in :notify mode" do
      payloads = []
      callback = ->(event) { payloads << event.payload }

      expected_location_path = __FILE__
      expected_location_lineno = __LINE__ + 2
      ActiveSupport::Notifications.subscribed(callback, "deprecated_association.active_record") do
        DATS::Car.new.deprecated_tyres
      end

      assert_equal 1, payloads.size
      payload = payloads.first

      assert_equal DATS::Car.reflect_on_association(:deprecated_tyres), payload[:reflection]
      assert_equal expected_location_path, payload[:location].path
      assert_equal expected_location_lineno, payload[:location].lineno
      assert_equal "The association DATS::Car#deprecated_tyres is deprecated, the method deprecated_tyres was invoked", payload[:message]
    end
  end

  class RaiseModeTest < ActiveRecord::TestCase
    def setup
      @original_mode = ActiveRecord::Associations::Deprecation.mode
      ActiveRecord::Associations::Deprecation.mode = :raise
    end

    def teardown
      ActiveRecord::Associations::Deprecation.mode = @original_mode
    end

    test "report raises an error in :raise mode" do
      error = assert_raises(ActiveRecord::DeprecatedAssociationError) do
        DATS::Car.new.deprecated_tyres
      end

      assert_match(/The association DATS::Car#deprecated_tyres is deprecated, the method deprecated_tyres was invoked (.+)\Z/, error.message)
    end
  end
end
