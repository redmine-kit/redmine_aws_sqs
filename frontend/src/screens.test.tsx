import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { KitTestRequest } from '@redmine-kit/plugin/testing';
import { ApiError } from '@redmine-kit/plugin';
import { CardHeaderActionsContext } from '@redmine-kit/plugin/host';
import { describe, expect, it } from 'vitest';
import { AwsSqsJobs } from './AwsSqsJobs';
import { countsError, disabled, jobs, resent } from './fixtures';
import { renderKit } from './test/render';

// The Jobs tab on the plugin's JSON as AwsSqsJobsController answers it.
const JOBS = 'GET /admin/aws/jobs.json';

describe('AwsSqsJobs', () => {
  it('shows the counts, when they were read, and the failed jobs', async () => {
    renderKit(<AwsSqsJobs />, { responses: { [JOBS]: jobs } });
    await screen.findByText('1,234');
    const queue = screen.getByRole('region', { name: 'キュー' });
    expect(within(queue).getByText('1,234')).toBeInTheDocument();
    expect(within(queue).getByRole('button', { name: 'DLQ 再処理を開始' })).toBeInTheDocument();
    const table = screen.getByRole('table', { name: '失敗したジョブ' });
    expect(within(table).getByText('Mailer#issue_add')).toBeInTheDocument();
    expect(within(table).getByText('Net::ReadTimeout')).toBeInTheDocument();
  });

  it('without SQS: the warning, no queue; no failed job: 表示するデータがありません', async () => {
    renderKit(<AwsSqsJobs />, { responses: { [JOBS]: disabled } });
    expect(await screen.findByText('REDMINE_SQS_QUEUE_URL が未設定のため、ジョブは標準の方法で実行します。')).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'キュー' })).toBeNull();
    expect(within(screen.getByRole('region', { name: '失敗したジョブ' })).getByText('表示するデータがありません')).toBeInTheDocument();
  });

  it('shows the error of the last refresh in place of the counts, without the redrive', async () => {
    renderKit(<AwsSqsJobs />, { responses: { [JOBS]: countsError } });
    await screen.findByText(/Aws::SQS::Errors::AccessDenied/);
    const queue = screen.getByRole('region', { name: 'キュー' });
    expect(within(queue).getByText(/Aws::SQS::Errors::AccessDenied/)).toBeInTheDocument();
    expect(within(queue).queryByRole('button', { name: 'DLQ 再処理を開始' })).toBeNull();
  });

  it('メール asks for the mail jobs only (?mail=1)', async () => {
    const user = userEvent.setup();
    const requests: KitTestRequest[] = [];
    renderKit(<AwsSqsJobs />, { requests, responses: { [JOBS]: jobs } });
    await user.click(await screen.findByRole('radio', { name: 'メール' }));
    expect(requests.some((r) => r.path === '/admin/aws/jobs.json' && r.query?.mail === '1')).toBe(true);
  });

  it('resends the checked jobs after the confirmation, and shows the notice', async () => {
    const user = userEvent.setup();
    const requests: KitTestRequest[] = [];
    renderKit(<AwsSqsJobs />, { requests, responses: { [JOBS]: jobs, 'POST /admin/aws/jobs/resend.json': resent } });
    await screen.findByText('Mailer#issue_add');
    await user.click(within(screen.getByRole('table', { name: '失敗したジョブ' })).getAllByRole('checkbox')[1]);
    expect(screen.getByText('1 件を選択')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: '再送信' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('選択したジョブ 1 件を再送信しますか？')).toBeInTheDocument();
    await user.click(within(dialog).getByRole('button', { name: '再送信' }));
    expect(await screen.findByText('1 件のジョブを再送信しました。')).toBeInTheDocument();
    expect(requests.filter((r) => r.method === 'post')).toEqual([{ method: 'post', path: '/admin/aws/jobs/resend.json', body: { ids: [12] } }]);
  });

  it("shows each record's error of a resend, and Redmine's refusal of an action", async () => {
    const user = userEvent.setup();
    renderKit(<AwsSqsJobs />, {
      responses: { [JOBS]: jobs, 'POST /admin/aws/jobs/redrive.json': new ApiError(422, ['SQS の API を呼べませんでした (X)。']) },
    });
    await user.click(await screen.findByRole('button', { name: 'DLQ 再処理を開始' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('DLQ 再処理を開始しますか？')).toBeInTheDocument();
    await user.click(within(dialog).getByRole('button', { name: 'DLQ 再処理を開始' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('SQS の API を呼べませんでした (X)。');
  });

  it("when the counts were read and Refresh are in the card's header; Refresh asks for no confirmation", async () => {
    const user = userEvent.setup();
    const requests: KitTestRequest[] = [];
    const header = document.body.appendChild(document.createElement('div'));
    renderKit(
      <CardHeaderActionsContext value={header}>
        <AwsSqsJobs />
      </CardHeaderActionsContext>,
      { requests, responses: { [JOBS]: jobs, 'POST /admin/aws/jobs/refresh.json': { notice: null, errors: [] } } },
    );
    expect(await within(header).findByText('更新: 2026/11/24 09:30')).toBeInTheDocument();
    await user.click(within(header).getByRole('button', { name: '最新の情報に更新' }));
    expect(requests.some((r) => r.method === 'post' && r.path === '/admin/aws/jobs/refresh.json')).toBe(true);
    header.remove();
  });

  it("asks before deleting the checked jobs' records, saying they can't be restored", async () => {
    const user = userEvent.setup();
    const requests: KitTestRequest[] = [];
    renderKit(<AwsSqsJobs />, { requests, responses: { [JOBS]: jobs, 'POST /admin/aws/jobs/destroy.json': { notice: '削除しました。', errors: [] } } });
    await screen.findByText('Mailer#issue_add');
    for (const box of within(screen.getByRole('table', { name: '失敗したジョブ' })).getAllByRole('checkbox').slice(1)) await user.click(box);
    await user.click(screen.getByRole('button', { name: '削除' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('選択したジョブ 2 件を削除しますか？')).toBeInTheDocument();
    expect(within(dialog).getByText('記録は元に戻せず、そのジョブは再送信できなくなります。')).toBeInTheDocument();
    await user.click(within(dialog).getByRole('button', { name: '削除' }));
    expect(await screen.findByText('削除しました。')).toBeInTheDocument();
    expect(requests.find((r) => r.method === 'post')).toEqual({ method: 'post', path: '/admin/aws/jobs/destroy.json', body: { ids: [12, 11] } });
  });

  it('resend is off without SQS', async () => {
    const user = userEvent.setup();
    renderKit(<AwsSqsJobs />, { responses: { [JOBS]: { ...disabled, failures: jobs.failures } } });
    await screen.findByText('Mailer#issue_add');
    await user.click(within(screen.getByRole('table', { name: '失敗したジョブ' })).getAllByRole('checkbox')[1]);
    expect(screen.getByRole('button', { name: '再送信' })).toBeDisabled();
    expect(screen.getByRole('button', { name: '削除' })).toBeEnabled();
  });

  it('is a skeleton while it loads, and the error state when it cannot be read', async () => {
    const { unmount } = renderKit(<AwsSqsJobs />, { responses: { [JOBS]: new Promise(() => {}) } });
    expect(screen.getAllByRole('status', { name: 'ロード中...' }).length).toBeGreaterThan(0);
    unmount();
    renderKit(<AwsSqsJobs />, { responses: { [JOBS]: new ApiError(500, []) } });
    expect(await screen.findByRole('button', { name: /再読み込み|再試行/ })).toBeInTheDocument();
  });
});
