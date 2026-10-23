import {paymentPanel} from './payments-ui.mjs';
export function analyticsView(root,ctx){
  const {h,button,panel,table,money,S,goClients}=ctx;
  const dataset=S.analytics,scope=dataset.scopes[S.analysisScope],pct=v=>v===null?'Нет окна':new Intl.NumberFormat('ru-RU',{style:'percent',maximumFractionDigits:1}).format(v);
  const compactMoney=v=>v===null?'Нет данных':new Intl.NumberFormat('ru-RU',{style:'currency',currency:'RUB',notation:'compact',maximumFractionDigits:2}).format(v/100);
  const tabs=[['payments','Оплаты CRM'],['summary','Показатели выгрузки'],['segments','Сегменты'],['cohorts','Когорты'],['matrix','ABC × XYZ']];
  function change(field,value){S[field]=value;ctx.render();}
  root.append(h('div',{class:'analytics-toolbar',hidden:S.analysisTab==='payments'},h('div',{class:'scope-switch',role:'group','aria-label':'Выборка аналитики'},...[
    ['all','Вся база · '+dataset.scopes.all.clients],['attended','Со состоявшимися · '+dataset.scopes.attended.clients]
  ].map(([id,label])=>button(label,()=>change('analysisScope',id),'scope-button',{'aria-pressed':String(S.analysisScope===id)}))),h('span',{class:'muted',text:'Срез '+dataset.cutoff.split('-').reverse().join('.')})),
  h('div',{class:'analysis-tabs',role:'group','aria-label':'Разделы аналитики'},...tabs.map(([id,label])=>button(label,()=>change('analysisTab',id),'scope-button',{'aria-pressed':String(S.analysisTab===id)}))));
  if(S.analysisTab==='payments'){root.append(paymentPanel(ctx));return;}
  const description=S.analysisScope==='all'?'Весь справочник, включая '+scope.notClassified+' карточек без состоявшихся обращений. '+dataset.source.anonymousExcluded+' записей без карточки клиента (включая удалённые) не входят в анализ.':'Карточки с состоявшимися обращениями; вся их наблюдаемая история до среза.';
  root.append(h('p',{class:'context',text:description}));
  function metric(label,value,note,exact=null){return h('div',{class:'analysis-metric'},h('span',{class:'muted',text:label}),h('strong',{text:value,title:exact}),h('span',{class:'muted',text:note}));}
  function bars(title,rows,value='clients',format=String){const max=Math.max(1,...rows.map(r=>r[value]));return panel(title,h('div',{class:'bar-list'},...rows.map(r=>h('div',{class:'bar-row'},h('div',{class:'bar-label'},h('span',{text:r.label??r.name??r.month}),h('strong',{text:format(r[value])})),h('meter',{min:0,max,value:r[value],'aria-label':(r.label??r.name??r.month)+': '+format(r[value])})))));}
  function sourceTotals(){return h('div',{class:'analysis-money'},...[
    ['sourceReportedPaidCents','Оплачено в Yclients'],['sourceReportedSpentCents','Потрачено в Yclients'],['sourceReportedBalanceCents','Баланс в Yclients']
  ].map(([field,label])=>{const v=scope.moneyTotals[field];return metric(label,money(v.value),v.coverage+' из '+scope.clients+' карточек · поле источника');}));}
  function monthChart(){const rows=scope.monthly,W=800,H=220,L=100,R=20,T=16,B=36,max=Math.max(1,...rows.map(r=>r.cost));
    const el=(tag,props,...children)=>{const n=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const[k,v]of Object.entries(props))n.setAttribute(k,String(v));children.forEach(c=>n.append(c instanceof Node?c:document.createTextNode(c)));return n;};
    const svg=el('svg',{viewBox:`0 0 ${W} ${H}`,class:'chart',role:'img','aria-label':'Стоимость состоявшихся услуг по месяцам'}),x=i=>L+(rows.length<=1?0:i*(W-L-R)/(rows.length-1)),y=v=>T+(H-T-B)*(1-v/max);
    for(let i=0;i<4;i++){const v=max*i/3;svg.append(el('line',{x1:L,x2:W-R,y1:y(v),y2:y(v),class:'chart-grid'}),el('text',{x:L-8,y:y(v)+4,'text-anchor':'end',class:'chart-label'},Math.round(v/100/1000)+' тыс. ₽'));}
    svg.append(el('path',{class:'chart-line',d:rows.map((r,i)=>(i?'L':'M')+x(i)+','+y(r.cost)).join(' ')}));
    const step=Math.max(1,Math.ceil(rows.length/6));rows.forEach((r,i)=>{svg.append(el('circle',{cx:x(i),cy:y(r.cost),r:3,class:'chart-dot'},el('title',{},r.month+': '+money(r.cost))));if(i%step===0||i===rows.length-1)svg.append(el('text',{x:x(i),y:H-10,'text-anchor':'middle',class:'chart-label'},r.month.slice(5)+'.'+r.month.slice(2,4)));});
    return panel('Динамика стоимости услуг',h('p',{class:'muted',text:'По дате состоявшейся записи; это стоимость услуг, а не кассовая выручка.'}),h('div',{class:'chart-scroll',tabindex:0,role:'region','aria-label':'График стоимости услуг. Прокручивается по горизонтали.'},svg),h('details',{class:'details'},h('summary',{text:'Значения по месяцам'}),table(['Месяц','Обращения','Клиенты','Стоимость'],rows.map(r=>h('tr',{},h('th',{scope:'row',text:r.month}),h('td',{text:r.records}),h('td',{text:r.clients}),h('td',{class:'num',text:money(r.cost)}))))));
  }
  if(S.analysisTab==='summary'){
    root.append(h('div',{class:'analysis-metrics'},metric('Карточки',scope.clients,'из них '+scope.attendingClients+' со состоявшимися обращениями'),metric('Обращения',scope.records,'неудалённые записи до среза'),metric('Стоимость услуг',compactMoney(scope.costCents),'за всю наблюдаемую историю',money(scope.costCents)),metric('Средняя стоимость',money(scope.averageCostCents),'стоимость / число обращений')),
      sourceTotals(),h('p',{class:'context',text:'Оплачено, Потрачено и Баланс — самостоятельные поля справочника. Они не подтверждают размер авансов, возвратов или выручки.'}),monthChart(),
      h('div',{class:'analysis-grid'},panel('Повторные обращения',h('div',{class:'analysis-fact'},h('strong',{text:pct(scope.attendingClients?scope.repeatClients/scope.attendingClients:null)}),h('span',{text:scope.repeatClients+' из '+scope.attendingClients+' обращавшихся карточек с 2+ записями'})),h('p',{class:'muted',text:'Включает обращения в тот же день и бесплатное сопровождение. Не показатель платёжного удержания.'})),panel('Возврат после первого обращения',...scope.returns.map(r=>h('div',{class:'summary-row'},h('span',{text:'За '+r.days+' дней'}),h('strong',{text:pct(r.rate)+' · '+r.returned+'/'+r.eligible}))),h('p',{class:'muted',text:'Повторная запись в другой день. Знаменатель — карточки с полным окном наблюдения.'}))),
      h('div',{class:'analysis-grid'},bars('Направления · число обращений',scope.directions,'records'),bars('Метки источника · число обращений',scope.sources,'records')));
  }
  if(S.analysisTab==='segments')root.append(h('div',{class:'analysis-grid'},bars('Частота обращений',scope.frequency),bars('Давность последнего обращения',scope.recency)),panel('Жизненный цикл',h('p',{class:'muted',text:dataset.method.life}),table(['Группа','Карточки','Стоимость услуг'],scope.life.map(r=>h('tr',{},h('th',{scope:'row',text:r.label}),h('td',{text:r.clients}),h('td',{class:'num',text:money(r.costCents)}))))));
  if(S.analysisTab==='cohorts'){
    root.append(panel('Когорты первого наблюдаемого обращения',h('p',{class:'muted',text:'Месяц первой состоявшейся записи; карточки без неё не образуют когорту. Возврат — обращение в другой день; молодые когорты исключены из ещё не завершённых окон.'}),table(['Когорта','Карточки','Возврат 30 д.','Возврат 60 д.','Возврат 90 д.','Стоимость за историю'],scope.cohorts.map(c=>h('tr',{},h('th',{scope:'row',text:c.month}),h('td',{text:c.clients}),...[c.r30,c.r60,c.r90].map(r=>h('td',{text:pct(r.rate)+(r.eligible?' · '+r.returned+'/'+r.eligible:'')})),h('td',{class:'num',text:money(c.cost)}))))),
      panel('Активность по возрасту когорты',h('p',{class:'muted',text:'Доля карточек с обращением в каждом 30-дневном интервале. Знаменатель — карточки с полным интервалом; 0–29 дней включает первый визит.'}),table(['Когорта',...Array.from({length:7},(_,i)=>i*30+'–'+(i*30+29)+' дней')],scope.cohorts.map(c=>h('tr',{},h('th',{scope:'row',text:c.month}),...c.windows.map(w=>{const rate=w.eligible?w.active/w.eligible:null;return h('td',{class:'heat-cell '+(rate===null?'heat-unready':rate>=.5?'heat-high':rate>0?'heat-low':''),text:pct(rate),'title':w.active+' / '+w.eligible});}))))));
  }
  if(S.analysisTab==='matrix'){
    if(scope.notClassified)root.append(button('Без состоявшихся обращений · '+scope.notClassified,()=>goClients({life:'no_visits'}),'text-button'));
    root.append(panel('ABC × XYZ',h('p',{class:'muted',text:dataset.method.abc}),h('p',{class:'muted',text:dataset.method.xyz}),
      table(['ABC / XYZ','X · 6+ обращений','Y · 2–5 обращений','Z · 1 обращение'],['A','B','C','N'].map(a=>h('tr',{},h('th',{scope:'row',text:a==='N'?'N · нулевая стоимость':a}),...['X','Y','Z'].map(z=>{const cell=scope.matrix.find(c=>c.abc===a&&c.xyz===z),label=[h('strong',{text:cell.clients+' карточек'}),h('span',{class:'muted',text:money(cell.costCents)})];return h('td',{},cell.clients?button(label,()=>goClients({matrix:a+z}),'matrix-cell'):h('div',{class:'matrix-cell'},label));}))))),
      h('p',{class:'context',text:'Нажми на ячейку, чтобы открыть соответствующие карточки CRM. Классы рассчитаны по всей базе с состоявшимися обращениями.'}));
  }
}
