# frozen_string_literal: true

# The plugin's tables: the records of failed jobs, and the queue counts that
# the Jobs tab shows, as the last refresh read them.
class CreateAwsSqsTables < ActiveRecord::Migration[8.1]
  def change
    create_job_failures
    create_table :aws_sqs_snapshots do |t|
      t.text :data, null: false
      t.datetime :fetched_at, null: false
    end
  end

  private

  def create_job_failures # rubocop:disable Metrics/MethodLength -- one table, one line per column
    create_table :aws_sqs_job_failures do |t|
      t.string :job_class, null: false
      t.string :job_id
      t.string :queue_name
      t.string :summary
      t.text :job_data, null: false
      t.string :error_class, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :enqueued_at
      t.datetime :failed_at, null: false
    end
    add_index :aws_sqs_job_failures, :failed_at
  end
end
