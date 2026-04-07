import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'me.big3.app',
  appName: 'big3.me',
  webDir: 'dist',
  server: {
    url: 'https://big3.me',
    cleartext: false,
  },
  ios: {
    contentInset: 'automatic',
    preferredContentMode: 'mobile',
    scheme: 'big3me',
    backgroundColor: '#1c1c1e',
  },
  backgroundColor: '#1c1c1e',
};

export default config;
