export const STAGES = Object.freeze([
  { id: 'unassigned', label: 'Без этапа' },
  { id: 'contact', label: 'Контакт' },
  { id: 'doctor', label: 'Подбор врача' },
  { id: 'booking', label: 'Запись' },
  { id: 'followup', label: 'Повторный контакт' },
  { id: 'closed', label: 'Завершено' },
]);
export const stageLabel = id => STAGES.find(s => s.id === id)?.label ?? 'Без этапа';
