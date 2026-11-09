# frozen_string_literal: true

# The shared entry of the Serverless administration menu (every Redmine
# Serverless plugin draws it; the first one matches).
get 'admin/serverless', to: 'serverless_admin#index'

get 'admin/serverless/jobs', to: 'serverless_jobs#index', as: 'serverless_jobs'
post 'admin/serverless/jobs/resend', to: 'serverless_jobs#resend', as: 'serverless_jobs_resend'
post 'admin/serverless/jobs/destroy', to: 'serverless_jobs#destroy', as: 'serverless_jobs_destroy'
post 'admin/serverless/jobs/redrive', to: 'serverless_jobs#redrive', as: 'serverless_jobs_redrive'
