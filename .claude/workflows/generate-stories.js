export const meta = {
  name: 'generate-stories',
  description: 'Сгенерировать N утренних историй Morning Ben (sonnet) в stories/',
  whenToUse: 'Ручная или регулярная генерация историй. args = число историй, по умолчанию 5.',
  phases: [
    { title: 'Generate', detail: 'один sonnet-агент по промпту generate_stories.md', model: 'sonnet' },
  ],
}

const raw = args && typeof args === 'object' ? (args.n ?? args.count) : args
const n = Number(raw) > 0 ? Math.floor(Number(raw)) : 5

phase('Generate')
const report = await agent(
  `Ты — генератор контента Morning Ben. Работай в корне текущего проекта
(там лежат generate_stories.md, interests.md, examples.md, stories/, state/).

1. Прочитай generate_stories.md — это твой основной промпт. Плейсхолдер
   {{N_STORIES}} в нём означает ${n}.
2. Прочитай interests.md, examples.md и state/shown_history.json (нет файла —
   считай пустым списком), как велит промпт.
3. Прочитай существующие stories/*.json и выпиши темы (поле topic) историй,
   которых ещё нет в shown_history — они уже ждут в очереди, их темы тоже
   нельзя повторять, как и показанные.
4. Прочитай state/feedback.json (нет файла — считай пустым списком) — это
   свободные сообщения Ольги боту с пожеланиями к историям. Возьми три
   самых свежих (последние в списке), свежие важнее старых, и применяй по
   правилам из раздела «Как понимать обратную связь» промпта: тематические
   пожелания сдвигают пропорции (больше, но не вся пачка), стилевые —
   действуют на все истории.
5. Для картинок (раздел «Картинки (Pinterest)» промпта) подгрузи тул
   поиска: ToolSearch "select:mcp__pinterest__pinterest_search". Если тула
   нет в сессии — генерируй истории без картинок, это допустимо.
6. Выполни промпт generate_stories.md: сгенерируй ровно ${n} историй и запиши
   каждую отдельным файлом в stories/ в формате из промпта. Существующие
   файлы не трогай.

Перед завершением сам проверь валидность записанных JSON (например,
python3 -m json.tool) — отдельного агента для этого нет.

Верни короткий отчёт: созданные файлы и их темы.`,
  { model: 'sonnet', phase: 'Generate', label: `generate ${n} stories` },
)

log(`Готово: запрошено ${n} историй`)
return { requested: n, report }
