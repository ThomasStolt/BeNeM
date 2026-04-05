/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        severity: {
          critical: '#dc2626',
          major: '#ea580c',
          minor: '#ca8a04',
          warning: '#eab308',
          informational: '#2563eb',
        },
      },
    },
  },
  plugins: [],
};
