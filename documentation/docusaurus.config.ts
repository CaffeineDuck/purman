import { themes as prismThemes } from "prism-react-renderer";
import type { Config } from "@docusaurus/types";
import type * as Preset from "@docusaurus/preset-classic";

const config: Config = {
  title: "Purman",
  tagline: "Monitor your containers with ease",
  favicon: "img/favicon.ico",

  url: "https://purman.samrid.me",
  baseUrl: "/",

  onBrokenLinks: "warn",
  onBrokenMarkdownLinks: "warn",

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: "en",
    locales: ["en"],
  },

  presets: [
    [
      "classic",
      {
        docs: {
          sidebarPath: "./sidebars.ts",
          editUrl:
            "https://github.com/caffeineduck/purman/edit/main/documentation/",
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    navbar: {
      title: "Purman",
      items: [
        {
          type: "docSidebar",
          sidebarId: "quickStartSidebar",
          position: "left",
          label: "Quick Start",
        },
        {
          href: "https://github.com/caffeineduck/purman",
          label: "GitHub",
          position: "right",
        },
      ],
    },
    footer: {
      style: "dark",
      links: [
        {
          title: "Docs",
          items: [
            {
              label: "Reference",
              to: "/docs/reference",
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} CaffeineDuck <hello@samrid.me>`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
