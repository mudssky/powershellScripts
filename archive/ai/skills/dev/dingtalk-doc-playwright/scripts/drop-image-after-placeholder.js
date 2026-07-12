async (page) => {
  const placeholder = process.env.DINGTALK_PLACEHOLDER
  const imagePath = process.env.DINGTALK_IMAGE_PATH
  if (!placeholder) throw new Error('请设置 DINGTALK_PLACEHOLDER')
  if (!imagePath) throw new Error('请设置 DINGTALK_IMAGE_PATH')

  const frame = page.frames().find((item) => item.url().includes('/note/edit'))
  if (!frame) throw new Error('未找到 /note/edit iframe')

  const escaped = placeholder.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const locator = frame
    .locator('div')
    .filter({ hasText: new RegExp(`^${escaped}`) })
    .first()

  await locator.scrollIntoViewIfNeeded()
  await page.waitForTimeout(300)
  await locator.drop({ files: imagePath })
  await page.waitForTimeout(2500)

  return await frame.evaluate((target) => {
    const text = document.body.innerText
    const images = [...document.querySelectorAll('img')]
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
      placeholderVisible: text.includes(target),
      visibleLargeImages: images.length,
    }
  }, placeholder)
}
