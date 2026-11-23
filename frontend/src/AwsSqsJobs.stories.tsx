import { kitError, kitStory, userEvent, within, type Meta, type StoryObj } from '@redmine-kit/plugin/storybook';
import { AwsSqsJobs } from './AwsSqsJobs';
import { countsError, disabled, jobs, jobsEn, resent } from './fixtures';

// Administration › AWS › Jobs (the manifest's /admin/aws/jobs, a tab of the page AWS): the queue's counts and the failed
// jobs, in the app's card with the page's title. The answers in the toolbar's language, as the server gives the counts'
// names in the user's.
const english = () => document.documentElement.lang === 'en';
const jobsAnswer = () => (english() ? jobsEn : jobs);

const meta = {
  title: 'Screens/AwsSqsJobs',
  component: AwsSqsJobs,
  ...kitStory({
    frame: 'card',
    bare: true,
    title: 'AWS',
    responses: {
      'GET /admin/aws/jobs.json': jobsAnswer,
      'POST /admin/aws/jobs/resend.json': resent,
      'POST /admin/aws/jobs/destroy.json': { notice: '削除しました。', errors: [] },
      'POST /admin/aws/jobs/refresh.json': { notice: null, errors: [] },
      'POST /admin/aws/jobs/redrive.json': { notice: 'DLQ 再処理を開始しました。', errors: [] },
    },
  }),
} satisfies Meta<typeof AwsSqsJobs>;

export default meta;
type Story = StoryObj<typeof meta>;

/** The counts, the redrive (the dead-letter queue has messages) and two failed jobs. */
export const Default: Story = {};

/** Two failed jobs checked: resend and delete. */
export const Selected: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByText('Mailer#issue_add');
    for (const box of canvas.getAllByRole('checkbox').slice(1)) await userEvent.click(box);
  },
};

/** A resend refused for one record: its error. */
export const ResendFailed: Story = {
  ...kitStory({
    responses: {
      'GET /admin/aws/jobs.json': jobsAnswer,
      'POST /admin/aws/jobs/resend.json': {
        notice: null,
        errors: ['Mailer#issue_add: SQS の API を呼べませんでした (Aws::SQS::Errors::AccessDenied)。詳しくはログを参照してください。'],
      },
    },
  }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByText('Mailer#issue_add');
    await userEvent.click(canvas.getAllByRole('checkbox')[1]);
    await userEvent.click(await canvas.findByRole('button', { name: /再送信|Resend/ }));
    const dialog = within(await within(canvasElement.ownerDocument.body).findByRole('dialog'));
    await userEvent.click(await dialog.findByRole('button', { name: /^(再送信|Resend)$/ }));
  },
};

/** The last refresh could not read the counts. */
export const CountsError: Story = kitStory({ responses: { 'GET /admin/aws/jobs.json': countsError } });

/** REDMINE_SQS_QUEUE_URL not set, no failed job. */
export const Disabled: Story = kitStory({ responses: { 'GET /admin/aws/jobs.json': disabled } });

/** A redrive refused (Redmine's 422 with the error). */
export const RedriveFailed: Story = kitStory({
  responses: { 'GET /admin/aws/jobs.json': jobsAnswer, 'POST /admin/aws/jobs/redrive.json': kitError(422, ['SQS の API を呼べませんでした (Aws::SQS::Errors::AccessDenied)。詳しくはログを参照してください。']) },
});

export const Loading: Story = kitStory({ state: 'loading' });

/** The tab couldn't be read. */
export const Failed: Story = kitStory({ state: 'error' });

/** Redmine refused (not a system administrator): 403. */
export const Forbidden: Story = kitStory({ state: 'forbidden' });
