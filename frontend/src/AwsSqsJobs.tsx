import { useState } from 'react';
import {
  AttrGrid,
  AttrGridSkeleton,
  Button,
  CardBody,
  CardSection,
  DataTable,
  DataTableSkeleton,
  EmptyState,
  Notice,
  RequestErrorState,
  SegmentedControl,
  Skeleton,
  SkeletonRegion,
  confirmAction,
  type DataTableColumn,
  type DataTableRowBase,
} from '@redmine-kit/ui';
import { CardHeaderActions, useApiErrorTexts, useKitMutation, useKitQuery, useT } from '@redmine-kit/plugin';
import { sqsPaths, type SqsActionJson, type SqsFailure, type SqsJobsJson } from './api';

// Administration › AWS › ジョブ (/admin/aws/jobs: the manifest's layout: admin screen with menu_item aws, its tab
// label_aws_sqs_jobs at position 20). The app draws the card, its header and the strip of the AWS tabs; this draws the
// tab's content, as Redmine's page does (app/views/aws_sqs_jobs/index.html.erb):
// - without REDMINE_SQS_QUEUE_URL, the warning that jobs run in Redmine's standard way (and no queue);
// - the card's header: when the counts were read and 最新の情報に更新 (reads them again: POST refresh);
// - キュー: the counts the last refresh stored (the page never calls SQS) and, while the dead-letter queue has messages,
//   DLQ 再処理を開始 (POST redrive, after 「よろしいですか？」); the error of the last refresh in their place;
// - 失敗したジョブ: すべて / メール (the page's ?mail=1), the last 100 failed jobs, checked rows resent (再送信, only with
//   SQS set) or their records deleted (削除), each after 「よろしいですか？」, as the page's buttons. Each action's notice
//   and errors (a resend: each record that failed, with the class of its error) show above the sections.
// Every value comes formatted by the server (Redmine's helpers); the actions are the page's, behind require_admin.

const LABEL_WIDTH = 175;

interface Row extends DataTableRowBase {
  failure: SqsFailure;
}

function useColumns(): DataTableColumn<Row>[] {
  const t = useT();
  return [
    // the rows to resend or delete (the page's ids[] check boxes)
    { key: 'check', type: 'check' },
    { key: 'job', label: t('label_aws_sqs_jobs_job'), type: 'text', value: (r) => r.failure.summary },
    { key: 'error', label: t('label_aws_sqs_jobs_error'), type: 'text', value: (r) => r.failure.error },
    { key: 'attempts', label: t('label_aws_sqs_jobs_attempts'), type: 'number', value: (r) => r.failure.attempts },
    { key: 'enqueued', label: t('label_aws_sqs_jobs_enqueued_at'), type: 'text', align: 'right', value: (r) => r.failure.enqueued_at },
    { key: 'failed', label: t('label_aws_sqs_jobs_failed_at'), type: 'text', align: 'right', value: (r) => r.failure.failed_at },
  ];
}

export function AwsSqsJobs() {
  const t = useT();
  const [mail, setMail] = useState(false);
  const query = useKitQuery<SqsJobsJson>(sqsPaths.jobs, mail ? { mail: '1' } : undefined);
  const action = useKitMutation<SqsActionJson>();
  const errorTexts = useApiErrorTexts();
  const [result, setResult] = useState<SqsActionJson | null>(null);
  const [selected, setSelected] = useState<string[]>([]);
  const columns = useColumns();

  const run = (path: string, body?: unknown) => {
    setResult(null);
    action.mutate(
      { method: 'post', path, body: body ?? {} },
      {
        onSuccess: (data) => {
          setResult(data ?? null);
          setSelected([]);
        },
      },
    );
  };
  // the confirmation names the action and its object; a second line only for what can't be undone
  const confirmRun = (label: string, message: string, path: string, body?: unknown, detail?: string) =>
    confirmAction({ title: label, message, detail, action: label, onConfirm: () => run(path, body) });

  const errors = [...(result?.errors ?? []), ...errorTexts(action.error)];
  if (query.isError)
    return (
      <CardBody>
        <RequestErrorState error={query.error} onRetry={() => void query.refetch()} retrying={query.isFetching} />
      </CardBody>
    );
  const data = query.data;
  const ids = selected.map(Number);
  return (
    <CardBody>
      {data?.enabled && (
        // when the counts were read and 最新の情報に更新: the tab's actions, in the card's header (the page's contextual
        // links at the top right; a section's heading would squeeze its title at a phone's width)
        <CardHeaderActions>
          {data.updated && <span className="text-meta text-text-muted">{t('label_aws_sqs_jobs_updated', { time: data.updated })}</span>}
          <Button icon="refresh" disabled={action.isPending} onClick={() => run(sqsPaths.refresh)}>
            {t('button_aws_sqs_jobs_refresh')}
          </Button>
        </CardHeaderActions>
      )}
      {data && !data.enabled && <Notice tone="warning" text={t('text_aws_sqs_jobs_disabled')} />}
      {result?.notice && <Notice tone="neutral" text={result.notice} />}
      {errors.length > 0 && <Notice tone="danger" role="alert" text={errors.join('\n')} wrap />}
      {!data ? (
        <JobsSkeleton columns={columns} />
      ) : (
        <>
          {data.enabled && (
            <CardSection
              line={false}
              heading={t('label_aws_sqs_jobs_queue')}
              actions={
                data.dead_letter && (
                  <Button size={28} disabled={action.isPending} onClick={() => confirmRun(t('button_aws_sqs_jobs_redrive'), t('text_aws_sqs_jobs_redrive_confirm'), sqsPaths.redrive)}>
                    {t('button_aws_sqs_jobs_redrive')}
                  </Button>
                )
              }
            >
              {data.counts ? (
                <div className="px-gutter">
                  <AttrGrid columns={1} labelWidth={LABEL_WIDTH} items={data.counts.map((row) => ({ label: row.name, value: row.value }))} />
                </div>
              ) : data.counts_error ? (
                <Notice tone="danger" text={data.counts_error} wrap />
              ) : (
                <EmptyState />
              )}
            </CardSection>
          )}
          <CardSection
            line={data.enabled}
            heading={t('label_aws_sqs_jobs_failures')}
            controls={
              <SegmentedControl
                size={28}
                aria-label={t('label_aws_sqs_jobs_failures')}
                value={mail ? 'mail' : 'all'}
                onValueChange={(value) => {
                  setMail(value === 'mail');
                  setSelected([]);
                }}
                items={[
                  { value: 'all', label: t('label_all') },
                  { value: 'mail', label: t('label_aws_sqs_jobs_mail_only') },
                ]}
              />
            }
          >
            {selected.length > 0 && (
              <Notice
                tone="neutral"
                icon="none"
                text={
                  <span className="flex min-w-0 flex-wrap items-center gap-2">
                    <span className="flex-none">{t('kit.common.selected_items', { count: selected.length })}</span>
                    <Button size={28} disabled={!data.enabled || action.isPending} onClick={() => confirmRun(t('button_aws_sqs_jobs_resend'), t('text_aws_sqs_jobs_resend_confirm', { count: ids.length }), sqsPaths.resend, { ids })}>
                      {t('button_aws_sqs_jobs_resend')}
                    </Button>
                    <Button size={28} variant="danger" disabled={action.isPending} onClick={() => confirmRun(t('button_delete'), t('text_aws_sqs_jobs_delete_confirm', { count: ids.length }), sqsPaths.destroy, { ids }, t('text_aws_sqs_jobs_delete_detail'))}>
                      {t('button_delete')}
                    </Button>
                  </span>
                }
              />
            )}
            {data.failures.length === 0 ? (
              <EmptyState />
            ) : (
              <DataTable<Row>
                label={t('label_aws_sqs_jobs_failures')}
                columns={columns}
                rows={data.failures.map((failure) => ({ id: String(failure.id), failure }))}
                selected={selected}
                onSelectionChange={setSelected}
              />
            )}
          </CardSection>
        </>
      )}
    </CardBody>
  );
}

/** The tab while its JSON loads: the queue's heading and its four counts, the failed jobs' heading and table. */
function JobsSkeleton({ columns }: { columns: DataTableColumn<Row>[] }) {
  const t = useT();
  return (
    <SkeletonRegion label={t('label_loading')}>
      <CardSection line={false} heading={t('label_aws_sqs_jobs_queue')}>
        <div className="px-gutter">
          <AttrGridSkeleton
            columns={1}
            labelWidth={LABEL_WIDTH}
            items={['waiting', 'running', 'delayed', 'dead_letter'].map((name) => ({ label: t(`label_aws_sqs_jobs_${name}`), width: 40 }))}
          />
        </div>
      </CardSection>
      <CardSection heading={t('label_aws_sqs_jobs_failures')} controls={<Skeleton width={120} height={28} />}>
        <DataTableSkeleton<Row> label={t('label_aws_sqs_jobs_failures')} loading={t('label_loading')} columns={columns} rows={3} />
      </CardSection>
    </SkeletonRegion>
  );
}
