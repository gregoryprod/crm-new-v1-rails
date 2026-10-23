export function createTasksView({h,button,request,S,render,openClient,openLead,date,moscowDay}){
 let rows=null,error='',loading=false,bucket='today',owner='',page=1;
 const groups=[['today','На сегодня'],['overdue','Просроченные'],['done','Выполненные'],['upcoming','Предстоящие'],['undated','Без срока']];
 const belongs=(t,id)=>id==='done'?t.status==='done':t.status==='open'&&(id==='today'?t.dueDay===moscowDay():id==='overdue'?t.dueDay&&t.dueDay<moscowDay():id==='upcoming'?t.dueDay>moscowDay():!t.dueDay);
 async function refresh(){loading=true;error='';if(S.view==='tasks')render();try{const data=await request('/api/tasks');if(data.batchId!==S.meta.batchId)throw Error('Изменился пакет клиентов. Перезагрузи CRM.');rows=data.tasks;}catch(e){error=e.message;}finally{loading=false;if(S.view==='tasks')render();}}
 function mount(root){
 root.append(h('p',{class:'context',text:'Задачи из всех карточек · сроки по московскому времени'}));
 const controls=h('div',{class:'task-toolbar'}),tabs=h('div',{class:'work-actions task-status-tabs',role:'group','aria-label':'Статус задач'});
 for(const[id,label]of groups)tabs.append(button(label+' · '+(rows??[]).filter(t=>belongs(t,id)).length,()=>{bucket=id;page=1;render();},'pill '+(bucket===id?'pill--primary':'pill--ghost'),{'aria-pressed':bucket===id}));
 const select=h('select',{'aria-label':'Ответственный за задачу',onchange:e=>{owner=e.target.value;page=1;render();}},h('option',{value:''},'Все ответственные'),h('option',{value:'none'},'Не назначен'),...[...new Set((rows??[]).map(t=>t.assignee).filter(Boolean))].sort().map(n=>h('option',{value:'name:'+n},n)));select.value=owner;
 controls.append(tabs,h('div',{class:'task-filter-row'},h('label',{class:'work-field'},h('span',{},'Ответственный за задачу'),select),button('Обновить',refresh,'pill pill--ghost',{disabled:loading})));root.append(controls);
 if(error)root.append(h('p',{role:'alert',class:'work-save-state--error',text:error}));
 if(loading){root.append(h('p',{role:'status',text:'Загружаем задачи…'}));return;}if(rows===null)return;
 const cards=new Map(S.cards.map(c=>[c.key,c]));const list=rows.filter(t=>belongs(t,bucket)&&(!owner||(owner==='none'?!t.assignee:t.assignee===owner.slice(5)))).filter(t=>{const c=cards.get(t.clientKey);return [t.title,t.description,t.leadName,t.leadPhone,c?.name,c?.phone,c?.petName,...(c?.patients??[]).map(p=>p.name)].join(' ').toLocaleLowerCase('ru').includes(S.query.trim().toLocaleLowerCase('ru'));}).sort((a,b)=>bucket==='done'?(b.completedAt??'').localeCompare(a.completedAt??''):(a.dueDay??'9999').localeCompare(b.dueDay??'9999')||a.createdAt.localeCompare(b.createdAt));
 if(!list.length){root.append(h('div',{class:'empty'},h('h2',{},'Задач пока нет'),h('p',{},'Создай задачу в карточке клиента или выбери другой статус и ответственного.')));return;}
 const size=25,pages=Math.max(1,Math.ceil(list.length/size));page=Math.min(page,pages);root.append(h('p',{class:'muted',text:'Найдено: '+list.length}));
 const items=h('div',{class:'global-tasks'});
 for(const t of list.slice((page-1)*size,page*size)){const c=cards.get(t.clientKey);items.append(h('article',{class:'global-task'},h('div',{},h('h2',{text:t.title}),t.description?h('p',{class:'work-body',text:t.description}):null,h('p',{class:'muted',text:'Срок: '+date(t.dueDay)+' · Ответственный: '+(t.assignee??'не назначен')}),t.status==='done'?h('p',{class:'muted',text:'Выполнено: '+new Date(t.completedAt).toLocaleString('ru-RU',{timeZone:'Europe/Moscow'})}):null),h('div',{},c?button(c.name||c.key,e=>openClient(c,e.currentTarget),'text-button'):t.leadId?button(t.leadName||'Открыть заявку',()=>openLead(t.leadId),'text-button'):h('span',{},'Клиент недоступен'),t.leadId&&c?button('Открыть заявку',()=>openLead(t.leadId),'text-button'):null,h('p',{class:'muted',text:(t.leadId?'Ответственный за заявку: ':'Ответственный за клиента: ')+(t.clientOwner??'не назначен')}))));}
 root.append(items,h('div',{class:'work-actions'},button('Назад',()=>{page--;render();},'pill pill--ghost',{disabled:page<=1}),h('span',{},page+' / '+pages),button('Дальше',()=>{page++;render();},'pill pill--ghost',{disabled:page>=pages})));
 }
 return {mount,refresh};
}
