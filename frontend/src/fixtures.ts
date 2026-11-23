import type { SqsActionJson, SqsJobsJson } from './api';

// The stories' and tests' data: the plugin's JSON as AwsSqsJobsController answers it (Japanese; the English story
// fixtures below).

export const jobs: SqsJobsJson = {
  enabled: true,
  updated: '2026/11/24 09:30',
  counts: [
    { name: '利用可能なメッセージ', value: '1,234' },
    { name: '処理中のメッセージ', value: '1' },
    { name: '遅延メッセージ', value: '0' },
    { name: 'デッドレターキュー', value: '2' },
  ],
  counts_error: null,
  dead_letter: true,
  failures: [
    { id: 12, summary: 'Mailer#issue_add', error: 'Net::ReadTimeout', attempts: 3, enqueued_at: '2026/11/24 08:58', failed_at: '2026/11/24 09:02' },
    { id: 11, summary: 'DestroyProjectJob', error: 'ActiveRecord::RecordNotFound', attempts: 3, enqueued_at: '-', failed_at: '2026/11/23 18:40' },
  ],
};

export const jobsEn: SqsJobsJson = {
  ...jobs,
  counts: [
    { name: 'Messages available', value: '1,234' },
    { name: 'Messages in flight', value: '1' },
    { name: 'Messages delayed', value: '0' },
    { name: 'Dead-letter queue', value: '2' },
  ],
};

// REDMINE_SQS_QUEUE_URL not set: no counts, the failed jobs still listed
export const disabled: SqsJobsJson = { enabled: false, updated: null, counts: null, counts_error: null, dead_letter: false, failures: [] };

// the last refresh could not read the counts
export const countsError: SqsJobsJson = {
  ...jobs,
  counts: null,
  dead_letter: false,
  counts_error: 'SQS の API を呼べませんでした (Aws::SQS::Errors::AccessDenied)。詳しくはログを参照してください。',
};

export const resent: SqsActionJson = { notice: '1 件のジョブを再送信しました。', errors: [] };
