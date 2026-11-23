// The plugin's JSON (AwsSqsJobsController): the paths the tab reads and writes, and the shapes of its answers.

/** The Jobs tab's JSON paths (config/routes.rb). */
export const sqsPaths = {
  /** GET: the counts and the failed jobs (?mail=1: the mail jobs only) */
  jobs: '/admin/aws/jobs.json',
  /** POST { ids }: resends the failed jobs */
  resend: '/admin/aws/jobs/resend.json',
  /** POST { ids }: deletes their records */
  destroy: '/admin/aws/jobs/destroy.json',
  /** POST: starts moving the dead-letter queue's messages back */
  redrive: '/admin/aws/jobs/redrive.json',
  /** POST: reads the queue's counts from SQS again */
  refresh: '/admin/aws/jobs/refresh.json',
};

/** A row of values (aws_admin/values' rows), formatted by the server. */
export interface SqsRow {
  name: string;
  value: string;
}

/** A failed job (AwsSqsJobFailure), its times formatted by the server (format_time; '-' when unknown). */
export interface SqsFailure {
  id: number;
  summary: string;
  error: string;
  attempts: number;
  enqueued_at: string;
  failed_at: string;
}

/** GET /admin/aws/jobs.json (AwsSqsJobsHelper#aws_sqs_jobs_json) */
export interface SqsJobsJson {
  /** REDMINE_SQS_QUEUE_URL is set */
  enabled: boolean;
  /** when the counts were read (format_time), or null */
  updated: string | null;
  counts: SqsRow[] | null;
  /** the error of reading them, as the page says it, or null */
  counts_error: string | null;
  /** the dead-letter queue has messages: the redrive's action */
  dead_letter: boolean;
  failures: SqsFailure[];
}

/** The answer of an action: its notice, and the errors (a resend: each record's). */
export interface SqsActionJson {
  notice: string | null;
  errors: string[];
}
