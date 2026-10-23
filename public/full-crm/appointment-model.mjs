// Native CRM activity is separate from the dated YCLIENTS export.
export const APPOINTMENT_LABELS={scheduled:'Запланирован',confirmed:'Подтверждён',arrived:'Клиент пришёл',completed:'Завершён',no_show:'Неявка'};
export const PAYMENT_METHODS={cash:'Наличные',card:'Карта',transfer:'Перевод'};
export const attendanceOf=b=>b.attendance??'scheduled';
export const editableBooking=b=>b.status==='active'&&['scheduled','confirmed'].includes(attendanceOf(b));
export const appointmentLabel=b=>b.status==='cancelled'?'Отменён':APPOINTMENT_LABELS[attendanceOf(b)];
export const nextAttendance=b=>b.status!=='active'?[]:({scheduled:['confirmed','arrived','no_show'],confirmed:['scheduled','arrived','no_show'],arrived:['completed'],completed:[],no_show:[]}[attendanceOf(b)]??[]);
export const moscowPaymentDay=p=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Moscow'}).format(new Date(p.paidAt));
export function paymentSummary(payments,{from='',to='',doctorId='',clientKey=''}={}){
 const rows=payments.filter(p=>(!from||moscowPaymentDay(p)>=from)&&(!to||moscowPaymentDay(p)<=to)&&(!doctorId||p.doctorId===doctorId)&&(!clientKey||p.clientKey===clientKey));
 const totalCents=rows.reduce((n,p)=>n+p.amountCents,0);
 return {rows:rows.slice().sort((a,b)=>b.paidAt.localeCompare(a.paidAt)),totalCents,count:rows.length,clients:new Set(rows.map(p=>p.clientKey??p.clientId??p.clientSourceId)).size,averageCents:rows.length?Math.round(totalCents/rows.length):null};
}
