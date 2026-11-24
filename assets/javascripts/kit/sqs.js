// Redmine Kit AWS SQS: the plugin's module for the new UI, built from frontend/src by `npm run build` (frontend/vite.config.js).
// Edit the source, not this file. React, @redmine-kit/ui and @redmine-kit/plugin come from the app (the shell's import map).
import { useState } from "react";
import { AttrGrid, AttrGridSkeleton, Button, CardBody, CardSection, DataTable, DataTableSkeleton, EmptyState, Notice, RequestErrorState, SegmentedControl, Skeleton, SkeletonRegion, confirmAction } from "@redmine-kit/ui";
import { CardHeaderActions, useApiErrorTexts, useKitMutation, useKitQuery, useT } from "@redmine-kit/plugin";
import { Fragment, jsx, jsxs } from "react/jsx-runtime";
// src/api.ts
/** The Jobs tab's JSON paths (config/routes.rb). */
var sqsPaths = {
	/** GET: the counts and the failed jobs (?mail=1: the mail jobs only) */
	jobs: "/admin/aws/jobs.json",
	/** POST { ids }: resends the failed jobs */
	resend: "/admin/aws/jobs/resend.json",
	/** POST { ids }: deletes their records */
	destroy: "/admin/aws/jobs/destroy.json",
	/** POST: starts moving the dead-letter queue's messages back */
	redrive: "/admin/aws/jobs/redrive.json",
	/** POST: reads the queue's counts from SQS again */
	refresh: "/admin/aws/jobs/refresh.json"
};
// src/AwsSqsJobs.tsx
var LABEL_WIDTH = 175;
function useColumns() {
	const t = useT();
	return [
		{
			key: "check",
			type: "check"
		},
		{
			key: "job",
			label: t("label_aws_sqs_jobs_job"),
			type: "text",
			value: (r) => r.failure.summary
		},
		{
			key: "error",
			label: t("label_aws_sqs_jobs_error"),
			type: "text",
			value: (r) => r.failure.error
		},
		{
			key: "attempts",
			label: t("label_aws_sqs_jobs_attempts"),
			type: "number",
			value: (r) => r.failure.attempts
		},
		{
			key: "enqueued",
			label: t("label_aws_sqs_jobs_enqueued_at"),
			type: "text",
			align: "right",
			value: (r) => r.failure.enqueued_at
		},
		{
			key: "failed",
			label: t("label_aws_sqs_jobs_failed_at"),
			type: "text",
			align: "right",
			value: (r) => r.failure.failed_at
		}
	];
}
function AwsSqsJobs() {
	const t = useT();
	const [mail, setMail] = useState(false);
	const query = useKitQuery(sqsPaths.jobs, mail ? { mail: "1" } : void 0);
	const action = useKitMutation();
	const errorTexts = useApiErrorTexts();
	const [result, setResult] = useState(null);
	const [selected, setSelected] = useState([]);
	const columns = useColumns();
	const run = (path, body) => {
		setResult(null);
		action.mutate({
			method: "post",
			path,
			body: body ?? {}
		}, { onSuccess: (data) => {
			setResult(data ?? null);
			setSelected([]);
		} });
	};
	const confirmRun = (label, message, path, body, detail) => confirmAction({
		title: label,
		message,
		detail,
		action: label,
		onConfirm: () => run(path, body)
	});
	const errors = [...result?.errors ?? [], ...errorTexts(action.error)];
	if (query.isError) return /* @__PURE__ */ jsx(CardBody, { children: /* @__PURE__ */ jsx(RequestErrorState, {
		error: query.error,
		onRetry: () => void query.refetch(),
		retrying: query.isFetching
	}) });
	const data = query.data;
	const ids = selected.map(Number);
	return /* @__PURE__ */ jsxs(CardBody, { children: [
		data?.enabled && /* @__PURE__ */ jsxs(CardHeaderActions, { children: [data.updated && /* @__PURE__ */ jsx("span", {
			className: "text-meta text-text-muted",
			children: t("label_aws_sqs_jobs_updated", { time: data.updated })
		}), /* @__PURE__ */ jsx(Button, {
			icon: "refresh",
			disabled: action.isPending,
			onClick: () => run(sqsPaths.refresh),
			children: t("button_aws_sqs_jobs_refresh")
		})] }),
		data && !data.enabled && /* @__PURE__ */ jsx(Notice, {
			tone: "warning",
			text: t("text_aws_sqs_jobs_disabled")
		}),
		result?.notice && /* @__PURE__ */ jsx(Notice, {
			tone: "neutral",
			text: result.notice
		}),
		errors.length > 0 && /* @__PURE__ */ jsx(Notice, {
			tone: "danger",
			role: "alert",
			text: errors.join("\n"),
			wrap: true
		}),
		!data ? /* @__PURE__ */ jsx(JobsSkeleton, { columns }) : /* @__PURE__ */ jsxs(Fragment, { children: [data.enabled && /* @__PURE__ */ jsx(CardSection, {
			line: false,
			heading: t("label_aws_sqs_jobs_queue"),
			actions: data.dead_letter && /* @__PURE__ */ jsx(Button, {
				size: 28,
				disabled: action.isPending,
				onClick: () => confirmRun(t("button_aws_sqs_jobs_redrive"), t("text_aws_sqs_jobs_redrive_confirm"), sqsPaths.redrive),
				children: t("button_aws_sqs_jobs_redrive")
			}),
			children: data.counts ? /* @__PURE__ */ jsx("div", {
				className: "px-gutter",
				children: /* @__PURE__ */ jsx(AttrGrid, {
					columns: 1,
					labelWidth: LABEL_WIDTH,
					items: data.counts.map((row) => ({
						label: row.name,
						value: row.value
					}))
				})
			}) : data.counts_error ? /* @__PURE__ */ jsx(Notice, {
				tone: "danger",
				text: data.counts_error,
				wrap: true
			}) : /* @__PURE__ */ jsx(EmptyState, {})
		}), /* @__PURE__ */ jsxs(CardSection, {
			line: data.enabled,
			heading: t("label_aws_sqs_jobs_failures"),
			controls: /* @__PURE__ */ jsx(SegmentedControl, {
				size: 28,
				"aria-label": t("label_aws_sqs_jobs_failures"),
				value: mail ? "mail" : "all",
				onValueChange: (value) => {
					setMail(value === "mail");
					setSelected([]);
				},
				items: [{
					value: "all",
					label: t("label_all")
				}, {
					value: "mail",
					label: t("label_aws_sqs_jobs_mail_only")
				}]
			}),
			children: [selected.length > 0 && /* @__PURE__ */ jsx(Notice, {
				tone: "neutral",
				icon: "none",
				text: /* @__PURE__ */ jsxs("span", {
					className: "flex min-w-0 flex-wrap items-center gap-2",
					children: [
						/* @__PURE__ */ jsx("span", {
							className: "flex-none",
							children: t("kit.common.selected_items", { count: selected.length })
						}),
						/* @__PURE__ */ jsx(Button, {
							size: 28,
							disabled: !data.enabled || action.isPending,
							onClick: () => confirmRun(t("button_aws_sqs_jobs_resend"), t("text_aws_sqs_jobs_resend_confirm", { count: ids.length }), sqsPaths.resend, { ids }),
							children: t("button_aws_sqs_jobs_resend")
						}),
						/* @__PURE__ */ jsx(Button, {
							size: 28,
							variant: "danger",
							disabled: action.isPending,
							onClick: () => confirmRun(t("button_delete"), t("text_aws_sqs_jobs_delete_confirm", { count: ids.length }), sqsPaths.destroy, { ids }, t("text_aws_sqs_jobs_delete_detail")),
							children: t("button_delete")
						})
					]
				})
			}), data.failures.length === 0 ? /* @__PURE__ */ jsx(EmptyState, {}) : /* @__PURE__ */ jsx(DataTable, {
				label: t("label_aws_sqs_jobs_failures"),
				columns,
				rows: data.failures.map((failure) => ({
					id: String(failure.id),
					failure
				})),
				selected,
				onSelectionChange: setSelected
			})]
		})] })
	] });
}
/** The tab while its JSON loads: the queue's heading and its four counts, the failed jobs' heading and table. */
function JobsSkeleton({ columns }) {
	const t = useT();
	return /* @__PURE__ */ jsxs(SkeletonRegion, {
		label: t("label_loading"),
		children: [/* @__PURE__ */ jsx(CardSection, {
			line: false,
			heading: t("label_aws_sqs_jobs_queue"),
			children: /* @__PURE__ */ jsx("div", {
				className: "px-gutter",
				children: /* @__PURE__ */ jsx(AttrGridSkeleton, {
					columns: 1,
					labelWidth: LABEL_WIDTH,
					items: [
						"waiting",
						"running",
						"delayed",
						"dead_letter"
					].map((name) => ({
						label: t(`label_aws_sqs_jobs_${name}`),
						width: 40
					}))
				})
			})
		}), /* @__PURE__ */ jsx(CardSection, {
			heading: t("label_aws_sqs_jobs_failures"),
			controls: /* @__PURE__ */ jsx(Skeleton, {
				width: 120,
				height: 28
			}),
			children: /* @__PURE__ */ jsx(DataTableSkeleton, {
				label: t("label_aws_sqs_jobs_failures"),
				loading: t("label_loading"),
				columns,
				rows: 3
			})
		})]
	});
}
export { AwsSqsJobs };
