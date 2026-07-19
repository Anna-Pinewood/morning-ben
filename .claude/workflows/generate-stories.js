export const meta = {
  name: 'generate-stories',
  description: 'Сгенерировать N утренних историй Morning Ben (sonnet) в stories/',
  whenToUse: 'Ручная или регулярная генерация историй. args = число историй, по умолчанию 5.',
  phases: [
    { title: 'Generate', detail: 'один sonnet-агент по промпту generate_stories.md', model: 'sonnet' },
    { title: 'Validate', detail: 'проверка схемы всех stories/*.json' },
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
4. Выполни промпт generate_stories.md: сгенерируй ровно ${n} историй и запиши
   каждую отдельным файлом в stories/ в формате из промпта. Существующие
   файлы не трогай.

Верни короткий отчёт: созданные файлы и их темы.`,
  { model: 'sonnet', phase: 'Generate', label: `generate ${n} stories` },
)

phase('Validate')
const check = await agent(
  `В корне текущего проекта проверь ВСЕ файлы stories/*.json одной командой
python3: каждый обязан быть валидным JSON с полями id (непустая строка),
topic (строка), generated_at (строка), messages (непустой массив непустых
строк). Верни итог.`,
  {
    model: 'haiku',
    effort: 'low',
    phase: 'Validate',
    label: 'validate stories',
    schema: {
      type: 'object',
      required: ['total', 'valid', 'invalid_files'],
      properties: {
        total: { type: 'number' },
        valid: { type: 'number' },
        invalid_files: { type: 'array', items: { type: 'string' } },
      },
    },
  },
)

log(`Готово: запрошено ${n}, в stories/ всего ${check.total} файлов, валидных ${check.valid}`)
return { requested: n, report, validation: check }
