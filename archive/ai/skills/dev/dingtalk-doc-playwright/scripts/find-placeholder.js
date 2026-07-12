async (page) => {
  const placeholder = process.env.DINGTALK_PLACEHOLDER
  if (!placeholder) throw new Error('请设置 DINGTALK_PLACEHOLDER')

  const frame = page.frames().find((item) => item.url().includes('/note/edit'))
  if (!frame) throw new Error('未找到 /note/edit iframe')

  return await frame.evaluate(async ({ target, verbose }) => {
    const scroller = document.querySelector('#layout_body')
    if (!scroller) throw new Error('未找到 #layout_body 滚动容器')

    const max = scroller.scrollHeight - scroller.clientHeight
    const step = Math.max(500, Math.floor(scroller.clientHeight * 0.75))

    for (let pos = 0; pos <= max + step; pos += step) {
      scroller.scrollTop = Math.min(pos, max)
      await new Promise((resolve) => setTimeout(resolve, 300))

      const candidates = [...document.querySelectorAll('body *')]
      const element = candidates.find((node) =>
        (node.innerText || node.textContent || '').trim().startsWith(target),
      )
      if (!element) continue

      element.scrollIntoView({ block: 'center' })
      await new Promise((resolve) => setTimeout(resolve, 200))
      const rect = element.getBoundingClientRect()
      return {
        ok: true,
        scrollTop: scroller.scrollTop,
        text: (element.innerText || element.textContent || '').slice(0, 120),
        rect: {
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
        },
      }
    }

    const result = {
      ok: false,
      scrollTop: scroller.scrollTop,
    }
    if (verbose) result.textTail = document.body.innerText.slice(-500)
    return result
  }, { target: placeholder, verbose: process.env.DINGTALK_VERBOSE === '1' })
}
