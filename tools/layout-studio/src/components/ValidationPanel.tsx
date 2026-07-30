import { useLayoutStudioStore } from "../store/layoutStudioStore";

/** § 21 — errors (block export) vs. warnings (don't), rendered together with a running count so
 * the Toolbar's Export button state is never a mystery. */
export function ValidationPanel() {
  const issues = useLayoutStudioStore((s) => s.issues);
  const errors = issues.filter((i) => i.level === "error");
  const warnings = issues.filter((i) => i.level === "warning");

  if (issues.length === 0) {
    return <div className="validation-panel validation-clean">No validation issues.</div>;
  }

  return (
    <div className="validation-panel">
      {errors.length > 0 && (
        <div className="validation-group validation-errors">
          <h4>{errors.length} Error{errors.length === 1 ? "" : "s"}</h4>
          <ul>
            {errors.map((issue, index) => (
              <li key={index}>
                <code>{issue.code}</code> {issue.message}
                {issue.layoutId && <span className="issue-scope"> ({issue.layoutId}{issue.slotId ? ` / ${issue.slotId}` : ""})</span>}
              </li>
            ))}
          </ul>
        </div>
      )}
      {warnings.length > 0 && (
        <div className="validation-group validation-warnings">
          <h4>{warnings.length} Warning{warnings.length === 1 ? "" : "s"}</h4>
          <ul>
            {warnings.map((issue, index) => (
              <li key={index}>
                <code>{issue.code}</code> {issue.message}
                {issue.layoutId && <span className="issue-scope"> ({issue.layoutId}{issue.slotId ? ` / ${issue.slotId}` : ""})</span>}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
