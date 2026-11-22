# Jobs

Redmine Kit AWS SQS runs Redmine's background jobs, such as sending email, deleting projects and webhooks, from one Amazon SQS queue, when the environment variable `REDMINE_SQS_QUEUE_URL` is set; without it, jobs run in Redmine's standard way. Only the job classes the plugins allow are run, whatever a message names. A job that fails for the last time is recorded, so that it can be sent again.

**Administration** › **AWS** › **Jobs** shows the queue and the failed jobs. Only administrators can open it, and each operation on it is written to Redmine's log.

## Queue

**Messages available**, **Messages in flight**, **Messages delayed** and the number of jobs in the **Dead-letter queue**, as they were last read (**Updated: …** at the top right). A scheduled rake task (`redmine_kit:aws:sqs:refresh`) reads them; **Refresh** reads them again at once. While the dead-letter queue has jobs, **Start DLQ redrive** moves them back to the job queue.

## Failed jobs

The latest 100 jobs that failed for the last time, all of them or only **Email**, with the **Job**, the class of the **Error**, the **Attempts**, **Enqueued at** and **Failed at**. Check jobs, then:

- **Resend** sends them to the job queue again (only while the queue is set).
- **Delete** deletes their records.

`redmine_kit:aws:sqs:prune` deletes the records of jobs that failed more than 90 days ago (`DAYS` to change it).
