import {isOverdue,workSummary} from './work-model.mjs';
const stamp=v=>v?new Intl.DateTimeFormat('ru-RU',{timeZone:'Europe/Moscow',day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'}).format(new Date(v)):'—';
const date=v=>v?v.split('-').reverse().join('.'):'Без срока';
const newTask=owner=>({title:'',description:'',dueDay:'',assignee:owner??''});
export function createClientWorkUI({h,button,request,batchId,isCurrent,onChange}){
  const states=new Map();
  function state(key){if(!states.has(key))states.set(key,{key,data:null,loading:false,saving:false,error:'',message:'',stale:false,ownerDraft:'',ownerDirty:false,profileDirty:false,profileDraft:null,task:newTask(null),taskDirty:false,comment:{text:'',author:''},commentDirty:false,editTask:null,editComment:null,composer:'task',showArchived:false,visibleComments:20,pending:new Map(),roots:null,sequence:0});return states.get(key);}
  const dirty=s=>s.ownerDirty||s.profileDirty||s.taskDirty||s.commentDirty;
  function hasDrafts(){return [...states.values()].some(dirty);}
  function apply(s,data){if(data.batchId!==batchId()||data.key!==s.key){s.stale=true;throw Error('Пакет клиентов изменился. Перезагрузи CRM.');}s.data=data;if(!s.profileDirty&&data.profile)s.profileDraft={name:data.profile.name??'',phone:data.profile.phone??'',email:data.profile.email??''};if(!s.ownerDirty)s.ownerDraft=data.owner??'';if(!s.taskDirty&&!s.editTask)s.task.assignee=data.owner??'';onChange(s.key,data.summary??workSummary(data),data.profile);}
  async function load(s){const sequence=++s.sequence;s.loading=true;s.error='';paint(s);try{const data=await request('/api/client-work?key='+encodeURIComponent(s.key));if(sequence===s.sequence)apply(s,data);}catch(e){if(sequence===s.sequence)s.error=e.message;}finally{if(sequence===s.sequence){s.loading=false;paint(s);}}}
  async function save(s,operation,payload,success){
    if(s.loading||s.saving||s.stale||!s.data)return;
    const signature=JSON.stringify([operation,payload]);if(!s.pending.has(signature))s.pending.set(signature,crypto.randomUUID());
    s.saving=true;s.error='';s.message='';paint(s);
    try{const data=await request('/api/client-work',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({batchId:batchId(),key:s.key,revision:s.data.revision,operation,operationId:s.pending.get(signature),payload})});apply(s,data);success?.();s.pending.delete(signature);s.message='Сохранено';}
    catch(e){s.error=e.message;if(e.status===409){try{const data=await request('/api/client-work?key='+encodeURIComponent(s.key));apply(s,data);}catch(refresh){s.error=refresh.message;}}}
    finally{s.saving=false;paint(s);}
  }
  function input(s,label,value,oninput,{id,max=120,type='text',required=false,area=false}={}){
    const field=h(area?'textarea':'input',{type:area?null:type,value:area?null:value,id,rows:area?3:null,maxlength:type==='date'?null:max,required,disabled:s.saving||s.loading||s.stale,'data-focus-id':id,oninput:e=>oninput(e.target.value)});if(area)field.value=value;
    return h('label',{class:'work-field'},h('span',{text:label}),field);
  }
  function action(s,label,operation,payload,success,props={}){return button(label,()=>save(s,operation,payload,success),'text-button',{disabled:s.saving||s.loading||s.stale,'data-focus-id':operation+'-'+(payload.id??'owner'),...props});}
  function owner(s){
    const form=h('form',{class:'owner-form',onsubmit:e=>{e.preventDefault();save(s,'set_owner',{owner:s.ownerDraft.trim()||null},()=>{s.ownerDirty=false;s.ownerDraft=s.data.owner??'';});}},
      input(s,'Ответственный за клиента',s.ownerDraft,v=>{s.ownerDraft=v;s.ownerDirty=v!==(s.data?.owner??'');const b=form.querySelector('button');b.disabled=!s.ownerDirty||s.saving||s.loading||s.stale;},{id:'client-owner'}),
      h('button',{type:'submit',class:'pill pill--ghost',disabled:s.saving||s.loading||s.stale||!s.ownerDirty,'data-focus-id':'save-owner',text:'Сохранить ответственного'}));
    return [h('h2',{class:'panel-title',text:'Ответственный'}),form,profileEditor(s),h('p',{class:'context',text:s.data?.owner?'Назначен вручную. Для снятия очисти поле и сохрани.':'Пока не назначен. Введи имя сотрудника.'})];
  }
  function profileEditor(s){
    if(!s.profileDraft)return h('p',{class:'context',text:'Контакты доступны в карточке клиента.'});
    const fields=[['name','Имя клиента'],['phone','Телефон'],['email','Email']];
    const form=h('form',{class:'work-composer',onsubmit:e=>{e.preventDefault();save(s,'update_profile',{name:s.profileDraft.name.trim(),phone:s.profileDraft.phone.trim(),email:s.profileDraft.email.trim()||null},()=>{s.profileDirty=false;s.profileDraft={name:s.data.profile.name??'',phone:s.data.profile.phone??'',email:s.data.profile.email??''};});}},h('h3',{text:'Контакты клиента'}),...fields.map(([key,label])=>input(s,label,s.profileDraft[key],value=>{s.profileDraft[key]=value;s.profileDirty=true;},{id:'client-profile-'+key,max:key==='name'?200:254,type:key==='email'?'email':key==='phone'?'tel':'text',required:key==='name'})),h('button',{class:'pill pill--ghost',type:'submit',disabled:s.saving||s.loading||s.stale,'data-focus-id':'save-profile',text:'Сохранить контакты'}),h('p',{class:'context',text:'Сохраняется в текущей базе CRM. Исходная выгрузка остаётся в истории.'}));
    return form;
  }
  function resetTask(s){s.task=newTask(s.data?.owner);s.taskDirty=false;s.editTask=null;}
  function resetComment(s){s.comment={text:'',author:s.comment.author};s.commentDirty=false;s.editComment=null;}
  function composer(s){
    const switcher=h('div',{class:'scope-switch',role:'group','aria-label':'Добавить в карточку'},...[
      ['task','Задача'],['comment','Комментарий']
    ].map(([id,label])=>button(label,()=>{s.composer=id;paint(s);},'scope-button',{'aria-pressed':String(s.composer===id),'data-focus-id':'work-composer-'+id,disabled:s.saving})));
    let form;
    if(s.composer==='task'){
      form=h('form',{class:'work-composer',onsubmit:e=>{e.preventDefault();save(s,s.editTask?'update_task':'create_task',{...(s.editTask?{id:s.editTask}:{}),title:s.task.title,description:s.task.description,dueDay:s.task.dueDay||null,assignee:s.task.assignee.trim()||null},()=>resetTask(s));}},
        input(s,'Что нужно сделать',s.task.title,v=>{s.task.title=v;s.taskDirty=true;},{id:'work-task-title',max:300,required:true}),
        input(s,'Подробности',s.task.description,v=>{s.task.description=v;s.taskDirty=true;},{id:'work-task-description',max:4000,area:true}),
        h('div',{class:'work-form-row'},input(s,'Срок до конца дня · МСК',s.task.dueDay,v=>{s.task.dueDay=v;s.taskDirty=true;},{id:'work-task-due',type:'date'}),input(s,'Исполнитель задачи',s.task.assignee,v=>{s.task.assignee=v;s.taskDirty=true;},{id:'work-task-assignee'})),
        h('div',{class:'work-actions'},h('button',{type:'submit',class:'pill',disabled:s.saving||s.stale,'data-focus-id':'submit-work-task',text:s.editTask?'Сохранить задачу':'Добавить задачу'}),button(s.editTask?'Отменить правки':'Очистить',()=>{resetTask(s);paint(s);},'text-button',{'data-focus-id':'work-clear-task',disabled:s.saving})));
    }else{
      form=h('form',{class:'work-composer',onsubmit:e=>{e.preventDefault();save(s,s.editComment?'update_comment':'create_comment',{...(s.editComment?{id:s.editComment}:{}),text:s.comment.text,author:s.comment.author.trim()||null},()=>resetComment(s));}},
        input(s,'Комментарий',s.comment.text,v=>{s.comment.text=v;s.commentDirty=true;},{id:'work-comment-text',max:5000,required:true,area:true}),
        input(s,'Подпись автора · необязательно',s.comment.author,v=>{s.comment.author=v;s.commentDirty=!!s.comment.text||!!s.editComment;},{id:'work-comment-author'}),
        h('div',{class:'work-actions'},h('button',{type:'submit',class:'pill',disabled:s.saving||s.stale,'data-focus-id':'submit-work-comment',text:s.editComment?'Сохранить комментарий':'Добавить комментарий'}),button(s.editComment?'Отменить правки':'Очистить',()=>{resetComment(s);paint(s);},'text-button',{'data-focus-id':'work-clear-comment',disabled:s.saving})));
    }
    return h('div',{class:'work-compose-area'},switcher,form);
  }
  function tasks(s){
    const all=s.data.tasks.filter(t=>s.showArchived||!t.archivedAt),sort=(a,b)=>(a.archivedAt?1:0)-(b.archivedAt?1:0)||(a.status==='done'?1:0)-(b.status==='done'?1:0)||(a.dueDay??'9999').localeCompare(b.dueDay??'9999')||b.createdAt.localeCompare(a.createdAt);
    const summary=workSummary(s.data),list=h('div',{class:'work-task-list'});
    for(const t of all.slice().sort(sort))list.append(h('article',{class:'work-task '+(t.status==='done'?'work-task--done':''),'data-task-id':t.id},
      h('div',{class:'work-item-heading'},h('h3',{text:t.title}),h('span',{class:'chip '+(isOverdue(t)?'chip--work':''),text:t.archivedAt?'Скрыта':t.status==='done'?'Выполнена':isOverdue(t)?'Просрочена':'Открыта'})),
      t.description?h('p',{class:'work-body',text:t.description}):null,
      h('p',{class:'context',text:'Срок: '+date(t.dueDay)+' · '+(t.assignee?'Исполнитель: '+t.assignee:'Исполнитель не назначен')}),
      h('div',{class:'work-actions'},t.archivedAt?action(s,'Восстановить','restore_task',{id:t.id}):[
        action(s,t.status==='done'?'Открыть снова':'Выполнить','set_task_status',{id:t.id,status:t.status==='done'?'open':'done'}),
        button('Изменить',()=>{if(s.taskDirty&&s.editTask!==t.id){s.error='Сначала сохрани или отмени текущие правки задачи.';paint(s);return;}s.task={title:t.title,description:t.description,dueDay:t.dueDay??'',assignee:t.assignee??''};s.editTask=t.id;s.composer='task';s.taskDirty=false;paint(s);s.roots.activity.querySelector('#work-task-title')?.focus();},'text-button',{disabled:s.saving}),
        action(s,'Скрыть','archive_task',{id:t.id},()=>{if(s.editTask===t.id)resetTask(s);})
      ])));
    return h('section',{class:'work-section'},h('div',{class:'work-section-heading'},h('h3',{text:'Задачи'}),h('span',{class:'context',text:summary.openTasks+' открытых · '+summary.overdueTasks+' просроченных'})),all.length?list:h('p',{class:'muted',text:'Задач пока нет. Добавь следующий шаг по клиенту.'}));
  }
  function comments(s){
    const rows=s.data.comments.filter(c=>s.showArchived||!c.archivedAt).slice().sort((a,b)=>b.createdAt.localeCompare(a.createdAt));
    const section=h('section',{class:'work-section'},h('h3',{text:'Комментарии'}));
    if(!rows.length){section.append(h('p',{class:'muted',text:'Комментарии пока не добавлены.'}));return section;}
    const list=h('div',{class:'work-comment-list'});
    for(const c of rows.slice(0,s.visibleComments)){
      const actions=c.archivedAt?[action(s,'Восстановить','restore_comment',{id:c.id})]:[
        button('Изменить',()=>{if(s.commentDirty&&s.editComment!==c.id){s.error='Сначала сохрани или отмени текущие правки комментария.';paint(s);return;}s.comment={text:c.text,author:c.author??''};s.editComment=c.id;s.commentDirty=false;s.composer='comment';paint(s);s.roots.activity.querySelector('#work-comment-text')?.focus();},'text-button',{disabled:s.saving}),
        action(s,'Скрыть','archive_comment',{id:c.id},()=>{if(s.editComment===c.id)resetComment(s);})
      ];
      list.append(h('article',{class:'work-comment','data-comment-id':c.id},h('div',{class:'work-item-heading'},h('strong',{text:c.author??'Автор не указан'}),h('span',{class:'context',text:stamp(c.createdAt)+(c.archivedAt?' · скрыт':c.updatedAt!==c.createdAt?' · изменён':'')})),h('p',{class:'work-body',text:c.text}),h('div',{class:'work-actions'},actions)));
    }
    section.append(list);
    if(rows.length>s.visibleComments)section.append(button('Ещё комментарии',()=>{s.visibleComments+=20;paint(s);},'text-button'));
    return section;
  }
  function paint(s){
    if(!s.roots||isCurrent()!==s.key)return;
    const active=document.activeElement,focus=s.roots.owner.contains(active)||s.roots.activity.contains(active)?active.dataset.focusId:null,selection=focus&&'selectionStart'in active?[active.selectionStart,active.selectionEnd]:null;
    const ready=!!s.data&&!s.loading;
    s.roots.owner.replaceChildren(...(ready?owner(s):[h('h2',{class:'panel-title',text:'Ответственный'}),h('p',{class:'muted',text:s.loading?'Загружаем рабочие записи…':'Рабочие записи не загружены.'})]));
    const status=h('p',{class:'work-save-state '+(s.error?'work-save-state--error':''),role:'status','aria-live':'polite',text:s.saving?'Сохраняем…':s.error||s.message});
    s.roots.activity.replaceChildren(...[h('h2',{class:'panel-title',text:'Работа с клиентом'}),status,...(ready?[
      composer(s),tasks(s),comments(s),h('label',{class:'check-filter'},h('input',{type:'checkbox',checked:s.showArchived,'data-focus-id':'work-show-archived',onchange:e=>{s.showArchived=e.target.checked;paint(s);}}),'Показать скрытые'),
      h('details',{class:'details'},h('summary',{text:'История изменений · '+s.data.events.length}),h('ol',{class:'work-audit'},...s.data.events.slice(-100).reverse().map(e=>h('li',{},h('span',{class:'context',text:stamp(e.at)}),h('span',{text:e.text})))))
    ]:[h('p',{class:'muted',text:s.loading?'Загружаем задачи и комментарии…':'Повтори загрузку. Существующие записи сохраняются в PostgreSQL.'})]),
    s.error&&!s.stale?button('Обновить записи',()=>load(s),'text-button',{disabled:s.saving||s.loading}):null,s.stale?button('Перезагрузить CRM',()=>location.reload(),'text-button'):null].filter(Boolean));
    if(focus){const el=s.roots.owner.querySelector('[data-focus-id="'+CSS.escape(focus)+'"]')??s.roots.activity.querySelector('[data-focus-id="'+CSS.escape(focus)+'"]');if(el&&!el.disabled){el.focus({preventScroll:true});if(selection&&selection[0]!==null&&['text','textarea'].includes(el.type))el.setSelectionRange(...selection);}else{status.tabIndex=-1;status.focus({preventScroll:true});}}
  }
  return {hasDrafts,detach(key){const s=states.get(key);if(s)s.roots=null;},open(key){const s=state(key);if(!s.saving)load(s);},mount(key){const s=state(key);const owner=h('section',{class:'work-owner'}),activity=h('section',{class:'work-activity'});s.roots={owner,activity};paint(s);return {owner,activity};}};
}
