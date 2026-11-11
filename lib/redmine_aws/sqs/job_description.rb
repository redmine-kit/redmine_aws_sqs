# frozen_string_literal: true

module RedmineAws
  module SQS
    # A job as Redmine's log shows it: the class, the job ID, the mailer and
    # the mail for email, and the arguments with secrets filtered. Built from
    # the job's serialized form (job.serialize, which is the message body).
    #
    # Arguments are named after the parameters of the job's perform, or of the
    # mailer method for email, and go through Rails' parameter filter
    # (config.filter_parameters, which Redmine sets to password, salt and
    # others), so that Mailer#account_information(user, password) is logged as
    # "user: gid://…/User/1, password: [FILTERED]". password is filtered even
    # when the application's filter lacks it. An argument without a known name
    # is filtered unless it refers to a record (a GlobalID), and long values
    # are cut, so that the log keeps identifiers, not contents.
    class JobDescription
      ALWAYS_FILTERED = %i[password].freeze
      MAIL_JOBS = %w[Mailer::DeliveryJob ActionMailer::MailDeliveryJob].freeze
      CLASS_NAME = /\A[A-Z]\w*(::[A-Z]\w*)*\z/
      METHOD_NAME = /\A[a-z_]\w*\z/

      # body: the message body; anything that is not a serialized job gives a
      # description without arguments.
      def self.from_body(body)
        data = JSON.parse(body.to_s)
        new(data.is_a?(Hash) ? data : {})
      rescue JSON::ParserError
        new({})
      end

      # A job that has not been serialized yet (ActiveJob's log lines). The
      # class is the job's own, so no name is looked up.
      def self.from_job(job)
        new(job.serialize, job_class: job.class)
      rescue StandardError
        # An argument that cannot be serialized: the job is described without
        # its arguments.
        new({ 'job_class' => job.class.name, 'job_id' => job.job_id })
      end

      def initialize(data, job_class: nil)
        @data = data
        @class = job_class
      end

      # A name that is not a constant path (the body is not trusted) is shown
      # as "unknown".
      def job_class
        name = @data['job_class'].to_s
        CLASS_NAME.match?(name) ? name : 'unknown'
      end

      def mail?
        MAIL_JOBS.include?(job_class)
      end

      # "Mailer#account_information(user: gid://…/User/1, password: [FILTERED])"
      # for email; "perform(project_id: 1, …)" otherwise.
      def call
        "#{mail? ? mail_name : 'perform'}(#{arguments})"
      end

      def to_s
        "#{job_class} (Job ID: #{@data['job_id'].to_s.first(64)}) #{call}"
      end

      def arguments
        filter(named_arguments).map { |name, value| "#{name}: #{JobArgument.format(value)}" }.join(', ')
      end

      # Whether the filter hides an argument (a password, an argument without
      # a known name): the job's serialized form then holds a secret
      # (AwsSqsJobFailure keeps it encrypted).
      def secret?
        filter(named_arguments).to_s.include?(JobArgument::FILTERED)
      end

      private

      def raw_arguments
        Array(@data['arguments'])
      end

      def mail_name
        mailer, method = raw_arguments.first(2).map(&:to_s)
        "#{CLASS_NAME.match?(mailer) ? mailer : 'unknown'}##{METHOD_NAME.match?(method) ? method : 'unknown'}"
      end

      # { name => plain value }: MailDeliveryJob's perform(mailer, mail_method,
      # delivery_method, args:, kwargs:, params:) gives the mail's arguments.
      def named_arguments
        if mail?
          options = JobArgument.plain(raw_arguments[3])
          options = {} unless options.is_a?(Hash)
          named(mail_method, Array(options['args'])).merge(keywords(options['kwargs']))
        else
          values = raw_arguments.map { |value| JobArgument.plain(value) }
          kwargs = values.last.is_a?(Hash) && keywords?(raw_arguments.last) ? values.pop : {}
          named(perform_method, values).merge(keywords(kwargs))
        end
      end

      # Positional values by the method's parameter names; a value without a
      # name keeps its position and is filtered unless it is a record.
      def named(method, values)
        names = method ? method.parameters.filter_map { |type, name| name if %i[req opt].include?(type) } : []
        values.each_with_index.to_h do |value, index|
          name = names[index]
          name ? [name.to_s, value] : ["arg#{index + 1}", JobArgument.identifier(value)]
        end
      end

      def keywords(hash)
        hash.is_a?(Hash) ? hash.transform_keys(&:to_s) : {}
      end

      def keywords?(value)
        value.is_a?(Hash) && value.key?('_aj_ruby2_keywords')
      end

      # The perform of a job class that may run from the queue; nil for
      # others, so that no name from the body is looked up.
      def perform_method
        klass = @class || (RedmineAws::SQS::Boot.allowed_jobs.include?(job_class) && job_class.safe_constantize)
        klass.instance_method(:perform) if klass.is_a?(Class) && klass.method_defined?(:perform)
      end

      # The mailer's method, for a mailer that is already loaded.
      def mail_method
        name, method = raw_arguments.first(2).map(&:to_s)
        mailer = ActionMailer::Base.descendants.find { |klass| klass.name == name }
        mailer.instance_method(method) if mailer&.action_methods&.include?(method)
      end

      def filter(hash)
        filters = Rails.application.config.filter_parameters + ALWAYS_FILTERED
        ActiveSupport::ParameterFilter.new(filters, mask: JobArgument::FILTERED).filter(hash)
      end
    end
  end
end
