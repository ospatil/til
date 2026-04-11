// @ts-check
import { defineConfig } from 'astro/config';
import { visit } from 'unist-util-visit';

function rehypeRewriteMdLinks() {
  return (tree) => {
    visit(tree, 'element', (node) => {
      if (node.tagName === 'a' && node.properties?.href) {
        node.properties.href = node.properties.href.replace(/\.md$/, '/');
      }
    });
  };
}

export default defineConfig({
  markdown: {
    rehypePlugins: [rehypeRewriteMdLinks],
  },
});
