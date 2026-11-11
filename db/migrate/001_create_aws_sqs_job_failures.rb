# frozen_string_literal: true

class CreateAwsSqsJobFailures < ActiveRecord::Migration[7.2]
  def change
    create_table :aws_sqs_job_failures do |t|
      t.string :job_class, null: false
      t.string :job_id
      t.string :queue_name
      t.string :summary
      t.text :job_data, null: false
      t.string :error_class, null: false
      t.text :error_message
      t.integer :attempts, null: false, default: 0
      t.datetime :enqueued_at
      t.datetime :failed_at, null: false
    end
    add_index :aws_sqs_job_failures, :failed_at
  end
end
