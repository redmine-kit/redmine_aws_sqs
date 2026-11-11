# frozen_string_literal: true

# The shared entry of the Serverless administration menu (every Redmine
# Serverless plugin draws it; the first one matches).
get 'admin/serverless', to: 'serverless_admin#index'

get 'admin/aws/jobs', to: 'aws_sqs_jobs#index', as: 'aws_sqs_jobs'
post 'admin/aws/jobs/resend', to: 'aws_sqs_jobs#resend', as: 'aws_sqs_jobs_resend'
post 'admin/aws/jobs/destroy', to: 'aws_sqs_jobs#destroy', as: 'aws_sqs_jobs_destroy'
post 'admin/aws/jobs/redrive', to: 'aws_sqs_jobs#redrive', as: 'aws_sqs_jobs_redrive'
