export const present = v => Number.isSafeInteger(v);
export const attended = r => !r.deleted && String(r.attendance).toLowerCase().replaceAll('ё','е') === 'пришел';
export function historySummary(cards) {
  const seen = new Set(), months = new Map(); let completed = 0, known = 0, sum = 0;
  for (const card of cards) for (const row of card.history ?? []) {
    if (seen.has(row.id)) continue; seen.add(row.id);
    if (!attended(row) || !/^\d{4}-\d{2}-\d{2}$/.test(row.date)) continue;
    completed++; const key=row.date.slice(0,7), item=months.get(key)??{month:key,sum:0,known:0,missing:0};
    if (present(row.costCents)) {item.sum+=row.costCents;item.known++;sum+=row.costCents;known++;} else item.missing++;
    months.set(key,item);
  }
  const keys=[...months.keys()].sort(), series=[];
  if(keys.length){let [y,m]=keys[0].split('-').map(Number);const last=keys.at(-1);for(let guard=0;guard<1200;guard++){const key=String(y).padStart(4,'0')+'-'+String(m).padStart(2,'0');if(key>last)break;series.push(months.get(key)??{month:key,sum:0,known:0,missing:0});if(++m===13){m=1;y++;}}}
  return {completed,known,sum,months:series};
}
export function sumKnown(cards,field) {
  const known=cards.filter(c=>present(c[field]));
  return {count:known.length,value:known.length?known.reduce((s,c)=>s+c[field],0):null};
}
