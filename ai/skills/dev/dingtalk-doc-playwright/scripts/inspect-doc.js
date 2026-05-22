async (page) => {
  const frame = page.frames().find((item) => item.url().includes('/note/edit'))
  if (!frame) return { ok: false, error: '未找到 /note/edit iframe' }

  return await frame.evaluate(() => {
    const text = document.body.innerText
    const scroller = document.querySelector('#layout_body')
    const largeImages = [...document.querySelectorAll('img')]
      .map((img) => {
        const rect = img.getBoundingClientRect()
        return {
          src: img.currentSrc || img.src || '',
          rect: {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
          },
        }
      })
      .filter(
        (item) =>
          item.rect.width > 300 &&
          item.rect.height > 200 &&
          item.src.includes('/core/api/resources/img/'),
      )

    return {
      ok: true,
      saved: text.includes('已保存'),
      title: document.title,
      wordCount: text.match(/\d+ 个字/)?.[0] ?? null,
      scroll: scroller
        ? {
            top: scroller.scrollTop,
            height: scroller.scrollHeight,
            clientHeight: scroller.clientHeight,
          }
        : null,
      visibleLargeImages: largeImages.length,
      textSample: text.slice(0, 1500),
      textTail: text.slice(-1500),
    }
  })
}

