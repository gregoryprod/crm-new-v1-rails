// All monetary amounts are integer minor units from CRM, never a payment ledger.
export const day = d => Date.parse(d+'T00:00:00Z') / 86400000;
export const LIFE = [
  {id:'first',label:'Первый визит'}, {id:'repeat',label:'Повторные'},
  {id:'regular',label:'Регулярные'}, {id:'dormant',label:'Давно не обращались'},
  {id:'no_visits',label:'Без состоявшихся обращений'},
];
export function lifecycle(records,days) {
  return records===0?'no_visits':days>=90?'dormant':records>=3?'regular':records===2?'repeat':'first';
}
export const xyz = n => n===0?null:n>=6?'X':n>=2?'Y':'Z';
export function abcAssignments(items) {
  const result=new Map(), positive=items.filter(p=>Number.isSafeInteger(p.cost)&&p.cost>0).sort((a,b)=>b.cost-a.cost||String(a.id).localeCompare(String(b.id)));
  const total=positive.reduce((s,p)=>s+p.cost,0);let cumulative=0;
  // Equal costs stay together; a boundary-crossing group belongs to the earlier class.
  for(let i=0;i<positive.length;){let j=i+1;while(j<positive.length&&positive[j].cost===positive[i].cost)j++;
    const group=positive.slice(i,j),kind=cumulative<total*.8?'A':cumulative<total*.95?'B':'C';
    for(const p of group)result.set(p.id,kind);cumulative+=group.reduce((s,p)=>s+p.cost,0);i=j;
  }
  for(const p of items)if(!result.has(p.id))result.set(p.id,p.cost===0?'N':'?');
  return result;
}
export function cardInsight(card,cutoff) {
  const events=card.history.filter(r=>!r.deleted&&r.attendance.replaceAll('ё','е')==='пришел'&&r.date<=cutoff).sort((a,b)=>a.date.localeCompare(b.date));
  const dates=[...new Set(events.map(r=>r.date))],known=events.filter(r=>Number.isSafeInteger(r.costCents));
  const cost=known.length===events.length?known.reduce((s,r)=>s+r.costCents,0):null;
  const days=events.length?day(cutoff)-day(events.at(-1).date):null,tenure=events.length?day(cutoff)-day(events[0].date):null;
  const returnAt=h=>({eligible:tenure!==null&&tenure>=h,returned:tenure!==null&&tenure>=h?dates.some(d=>day(d)>day(dates[0])&&day(d)-day(dates[0])<=h):null});
  return {records:events.length,uniqueDays:dates.length,cost,averageCostCents:cost===null||!events.length?null:Math.round(cost/events.length),daysSince:days,tenureDays:tenure,
    cohort:events[0]?.date.slice(0,7)??null,lifecycle:lifecycle(events.length,days),xyz:xyz(events.length),
    averageGapDays:dates.length>1?Math.round((day(dates.at(-1))-day(dates[0]))/(dates.length-1)):null,
    zeroCost:known.filter(r=>r.costCents===0).length,deleted:card.history.filter(r=>r.deleted).length,
    nonAttended:card.history.filter(r=>!r.deleted&&r.attendance.replaceAll('ё','е')!=='пришел').length,
    doctors:new Set(events.map(r=>r.doctorId??r.doctor)).size,petNames:[...new Set(card.history.map(r=>r.petName).filter(Boolean))],
    cost90Cents:events.filter(r=>day(cutoff)-day(r.date)<90).every(r=>Number.isSafeInteger(r.costCents))?events.filter(r=>day(cutoff)-day(r.date)<90).reduce((s,r)=>s+r.costCents,0):null,
    return30:returnAt(30),return60:returnAt(60),return90:returnAt(90)};
}
