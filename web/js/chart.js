// Hand-rolled SVG line chart. No library — it has to work offline forever.

function niceStep(range) {
  if (range <= 0) return 1;
  const raw = range / 4;
  const mag = Math.pow(10, Math.floor(Math.log10(raw)));
  const norm = raw / mag;
  const step = norm >= 5 ? 10 : norm >= 2 ? 5 : norm >= 1 ? 2 : 1;
  return step * mag;
}

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// points: [{ t: timestamp, v: number }] in ascending time order
export function lineChart(points, opts = {}) {
  const W = 320;
  const H = 190;
  const padL = 34;
  const padR = 10;
  const padT = 14;
  const padB = 26;

  if (!points.length) {
    return '<p class="empty">No data yet — log this exercise and it will show up here.</p>';
  }

  const values = points.map((p) => p.v);
  let min = Math.min(...values);
  let max = Math.max(...values);

  if (min === max) { min = min - 1; max = max + 1; }
  const step = niceStep(max - min);
  min = Math.floor(min / step) * step;
  max = Math.ceil(max / step) * step;

  const plotW = W - padL - padR;
  const plotH = H - padT - padB;

  const x = (i) => (points.length === 1 ? padL + plotW / 2 : padL + (i / (points.length - 1)) * plotW);
  const y = (v) => padT + plotH - ((v - min) / (max - min)) * plotH;

  let grid = '';
  let labels = '';
  for (let v = min; v <= max + 1e-9; v += step) {
    const gy = y(v).toFixed(1);
    grid += `<line x1="${padL}" y1="${gy}" x2="${W - padR}" y2="${gy}" class="grid"/>`;
    const txt = Math.round(v * 100) / 100;
    labels += `<text x="${padL - 6}" y="${(parseFloat(gy) + 3.5).toFixed(1)}" class="ylab">${txt}</text>`;
  }

  const path = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(p.v).toFixed(1)}`).join(' ');
  const area = `${path} L${x(points.length - 1).toFixed(1)},${padT + plotH} L${x(0).toFixed(1)},${padT + plotH} Z`;

  const dots = points
    .map((p, i) => `<circle cx="${x(i).toFixed(1)}" cy="${y(p.v).toFixed(1)}" r="4.5" class="dot"><title>${esc(p.label || p.v)}</title></circle>`)
    .join('');

  const fmtDate = (t) => new Date(t).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
  let xlabels = `<text x="${x(0).toFixed(1)}" y="${H - 8}" class="xlab" text-anchor="start">${fmtDate(points[0].t)}</text>`;
  if (points.length > 1) {
    xlabels += `<text x="${x(points.length - 1).toFixed(1)}" y="${H - 8}" class="xlab" text-anchor="end">${fmtDate(points[points.length - 1].t)}</text>`;
  }

  return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(opts.aria || 'Progress chart')}">
    ${grid}${labels}
    <path d="${area}" class="area"/>
    <path d="${path}" class="line"/>
    ${dots}${xlabels}
  </svg>`;
}
