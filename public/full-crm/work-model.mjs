export const moscowDay=(at=new Date())=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Moscow',year:'numeric',month:'2-digit',day:'2-digit'}).format(at);
export function validDay(value){return typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T00:00:00Z'))&&new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;}
export const isOverdue=(task,today=moscowDay())=>!task.archivedAt&&task.status==='open'&&!!task.dueDay&&task.dueDay<today;
export function workSummary(record,today=moscowDay()){
  const open=record.tasks.filter(t=>!t.archivedAt&&t.status==='open');
  return {revision:record.revision??0,owner:record.owner,openTasks:open.length,overdueTasks:open.filter(t=>isOverdue(t,today)).length,nextDueDay:open.map(t=>t.dueDay).filter(Boolean).sort()[0]??null,lastActivityAt:record.updatedAt??null};
}
export function mergeWorkIndex(index,recent){const result={...index};for(const [key,value]of Object.entries(recent))if(!result[key]||(value.revision??0)>(result[key].revision??0))result[key]=value;return result;}
