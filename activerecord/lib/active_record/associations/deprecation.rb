# frozen_string_literal: true

require "active_support/notifications"
require "active_support/core_ext/array/conversions"

module ActiveRecord::Associations::Deprecation # :nodoc:
  EVENT = "deprecated_association.active_record"
  private_constant :EVENT

  MODES = [:warn, :raise, :notify].freeze
  private_constant :MODES

  class << self
    attr_reader :mode

    def mode=(value)
      unless MODES.include?(value)
        raise ArgumentError, "Invalid deprecated associations mode #{value.inspect}. Valid modes are #{MODES.map(&:inspect).to_sentence}."
      end

      @mode = value
    end

    def guard(reflection)
      report(reflection, context: yield) if reflection.deprecated?

      if reflection.through_reflection?
        reflection.deprecated_nested_reflections.each do |deprecated_nested_reflection|
          report(
            deprecated_nested_reflection,
            context: "referenced as nested association of the through #{reflection.active_record}##{reflection.name}"
          )
        end
      end
    end

    def report(reflection, context:)
      message = "The association #{reflection.active_record}##{reflection.name} is deprecated, #{context}"

      case @mode
      when :warn
        first_clean_frame = ActiveRecord::LogSubscriber.backtrace_cleaner.first_clean_frame
        ActiveRecord::Base.logger&.warn("#{message} (#{first_clean_frame})")
      when :raise
        first_clean_frame = ActiveRecord::LogSubscriber.backtrace_cleaner.first_clean_frame
        raise ActiveRecord::DeprecatedAssociationError.new("#{message} (#{first_clean_frame})")
      else
        first_clean_location = ActiveRecord::LogSubscriber.backtrace_cleaner.first_clean_location
        ActiveSupport::Notifications.instrument(EVENT, reflection: reflection, location: first_clean_location, message: message)
      end
    end
  end

  self.mode = :warn
end
