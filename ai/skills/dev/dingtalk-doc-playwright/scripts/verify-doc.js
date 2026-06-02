async (page) => {
  const placeholders = (process.env.DINGTALK_PLACEHOLDERS || '')
    .split('|')
    .map((item) => item.trim())
    .filter(Boolean)

  const frame = page.frames().find((item) => item.url().includes('/note/edit'))
  if (!frame) throw new Error('未找到 /note/edit iframe')

  return await frame.evaluate(async (targets) => {
    const scroller = document.querySelector('#layout_body')
    if (!scroller) throw new Error('未找到 #layout_body 滚动容器')

    const max = scroller.scrollHeight - scroller.clientHeight
    const step = Math.max(400, Math.floor(scroller.clientHeight * 0.5))
    const seenText = new Set()
    const imageSrcs = new Set()

    for (let pos = 0; pos <= max + step; pos += step) {
      scroller.scrollTop = Math.min(pos, max)
      await new Promise((resolve) => setTimeout(resolve, 300))

      const text = document.body.innerText
      for (const target of targets) {
        if (text.includes(target)) seenText.add(target)
      }

      for (const img of document.querySelectorAll('img')) {
        const rect = img.getBoundingClientRect()
        const src = img.currentSrc || img.src || ''
        if (
          rect.width > 300 &&
          rect.height > 200 &&
          src.includes('/core/api/resources/img/')
        ) {
          imageSrcs.add(src)
        }
      }
    }

    return {
      ok: true,
      saved: document.body.innerText.includes('已保存'),
      placeholdersSeen: [...seenText],
      imageCount: imageSrcs.size,
      wordCount: document.body.innerText.match(/\d+ 个字/)?.[0] ?? null,
    }
  }, placeholders)
}

