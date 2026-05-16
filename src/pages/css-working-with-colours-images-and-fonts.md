---
layout: ../layouts/GistLayout.astro
tags: [css]
---

# CSS - working with colours, images and fonts

Colours

- When it comes to colour format, HSL format is modern intuitive way to define colours and many modern libraries (like shadcn) use it.
- HSL tutorial - https://www.joshwcomeau.com/css/color-formats/#hsl-4
- Another good tutorial for HSL, especially how to use it dynamically - https://blog.logrocket.com/using-hsl-colors-css/
- Colour picker for day-to-day working - https://hslpicker.com/
- Here is a good reference chart pdf -
    
    [Color Wheel Chart 10-10-86eqk3kzz.pdf](Color_Wheel_Chart_10-10-86eqk3kzz.pdf)
    

Images

- Generate *favicon* using - https://favicon.io/
- For background images that don’t need transparency, *jpeg* files at 1920 x 1080 resolution (at 80% quality) are more than 90% smaller than corresponding *png* files. Use https://squoosh.app/ to convert *png* files to *jpg.* It’s an image optimizer by Google Chrome Labs. It also had a NodeJS CLI tool `@squoosh/cli`, but it’s no longer maintained.
- For images that require transparency, such as logos etc, *webp* files at almost 50% smaller than their *png* counterparts. Use https://developers.google.com/speed/webp/docs/cwebp cli tool to convert *pngs* to *webp*. Install it using `brew install webp` and use it like - `cwebp -lossless input.png -o output.webp`
- There are some high quality open-source tools for image editing and manipulation like https://imagemagick.org/ and it’s modern alternative https://www.libvips.org/. Libvips can also be used directly in NodeJS using https://www.npmjs.com/package/sharp binding.
    
    These can be installed on Mac using `brew install imagemagick vips mozjpeg`
    

Fonts

- Many times, the component libraries being used have a preference for a font. If the app is behind a CDN like CloudFront, it’s a good idea to self-host and serve the fonts as static resources instead of linking to external CDNS. It can be done using https://fontsource.org/.
- Should there be a need to use google font, what’s the best way to include those - as a `link` tag or `@import` in a stylesheet? https://stackoverflow.com/a/12380004
- System fonts could be the fastest option since there is no font downloading. It can be tried out using - https://modernfontstacks.com/
