import {PAYMENT_METHODS,paymentSummary} from './appointment-model.mjs';
export function paymentPanel(ctx,client=null){
 const {h,button,panel,table,money,S}=ctx;
 const refresh=button(S.financeLoading?'Обновляем…':'Обновить оплаты',ctx.refreshFinance,'text-button',{disabled:S.financeLoading});
 if(!S.finance||S.financeError)return panel('Оплаты услуг · CRM',h('p',{role:'status',class:'muted',text:S.financeError||'Загружаем оплаты…'}),refresh);
 const filters=client?{clientKey:client.key}:{from:S.paymentFrom??'',to:S.paymentTo??'',doctorId:S.paymentDoctor??''};
 const badRange=filters.from&&filters.to&&filters.from>filters.to;
 const result=paymentSummary(S.finance.payments,filters),rows=result.rows;
 const box=panel('Оплаты услуг · CRM',h('p',{class:'context',text:'Только вручную зафиксированные оплаты завершённых приёмов, ₽. Период — по дате фиксации оплаты, московское время. Авансы, возвраты и поля выгрузки YCLIENTS сюда не входят.'}));
 if(!client){const field=(label,input)=>h('label',{class:'work-field'},h('span',{},label),input),change=(key,value)=>{S[key]=value;ctx.render();},docs=new Map(S.finance.payments.map(p=>[p.doctorId,p.doctorName]));
 const doctor=h('select',{'aria-label':'Врач в оплатах',onchange:e=>change('paymentDoctor',e.target.value)},h('option',{value:''},'Все врачи'),...[...docs].map(([id,name])=>h('option',{value:id},name)));doctor.value=S.paymentDoctor??'';
 box.append(h('div',{class:'calendar-form-grid'},field('Оплаты с',h('input',{type:'date',value:S.paymentFrom??'',onchange:e=>change('paymentFrom',e.target.value)})),field('Оплаты по',h('input',{type:'date',value:S.paymentTo??'',onchange:e=>change('paymentTo',e.target.value)})),field('Врач',doctor),refresh));
 }else box.append(refresh);
 if(badRange){box.append(h('p',{role:'alert',text:'Начало периода должно быть раньше окончания.'}));return box;}
 box.append(h('div',{class:'money-grid'},...[
 ['Оплачено услуг',money(result.totalCents)],['Платежи',result.count],['Клиенты',result.clients],['Средняя оплата',money(result.averageCents)]
 ].map(([label,value])=>h('div',{class:'money-cell'},h('span',{class:'muted',text:label}),h('strong',{text:value})))));
 if(!rows.length){box.append(h('p',{class:'muted',text:client?'У клиента пока нет зафиксированных в CRM оплат услуг.':'За выбранный период зафиксированных оплат нет.'}));return box;}
 box.append(table(['Зафиксировано, МСК',...(client?[]:['Клиент']),'Услуга / врач','Способ','Оплата, ₽'],rows.map(p=>{const c=S.cards.find(c=>c.key===p.clientKey);return h('tr',{},h('td',{text:new Date(p.paidAt).toLocaleString('ru-RU',{timeZone:'Europe/Moscow'})}),...(client?[]:[h('td',{},c?button(c.name||c.key,e=>ctx.openClient(c,e.currentTarget),'text-button'):h('span',{},p.clientName))]),h('td',{},h('strong',{text:p.title}),h('p',{class:'muted',text:p.doctorName}),p.note?h('p',{class:'work-body',text:p.note}):null),h('td',{text:PAYMENT_METHODS[p.method]}),h('td',{class:'num',text:money(p.amountCents)}));})));
 return box;
}
