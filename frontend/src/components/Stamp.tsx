/**
 * The registrar's stamp - the one place this UI spends its boldness. A verification
 * result is not a toast or a badge here; it is stamped onto the page in ink.
 */
export function Stamp({ ok, reason }: { ok: boolean; reason: string }) {
  return (
    <div className="stamp-row" role="status">
      <div className={`stamp ${ok ? "stamp-valid" : "stamp-invalid"}`}>
        <span className="stamp-word">{ok ? "VALID" : "INVALID"}</span>
      </div>
      <div className="stamp-caption">
        <span className="eyebrow">registry says</span>
        <span className="stamp-reason">{reason}</span>
      </div>
    </div>
  );
}
