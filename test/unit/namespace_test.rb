# frozen_string_literal: true

require_relative '../test_helper'
require 'open3'

module RedmineKitAws
  module SQS
    # The plugin's code is under the RedmineKitAws namespace of redmine_kit_aws
    # (lib/redmine_kit_aws/sqs.rb), and its boot file defines
    # RedmineKitAws::SQS::Boot before Redmine's code loader (Zeitwerk) starts,
    # as in the test image. Checked in new processes, as at start-up.
    class NamespaceTest < ActiveSupport::TestCase
      def rails(*)
        out, status = Open3.capture2e({ 'RAILS_ENV' => 'test' }, 'bin/rails', *, chdir: Rails.root.to_s)
        assert status.success?, out
        out
      end

      def test_zeitwerk_loads_every_file
        assert_includes rails('zeitwerk:check'), 'All is good!'
      end

      def test_both_plugins_start_with_the_boot_file_loaded
        script = 'print RedmineKitAws::VERSION, " ", RedmineKitAws::SQS::VERSION, " ", ' \
                 'RedmineKitAws::SQS::Boot.name, " ", RedmineKitAws::Admin.tabs.map(&:name).join(",")'

        assert_equal "#{RedmineKitAws::VERSION} #{VERSION} RedmineKitAws::SQS::Boot status,jobs",
                     rails('runner', script).lines.last.to_s.strip
      end
    end
  end
end
