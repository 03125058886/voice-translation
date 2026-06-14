import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import { Toaster } from 'react-hot-toast';
import './globals.css';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'VoiceTranslate — Real-time Multilingual Voice Calls',
  description:
    'Break language barriers with AI-powered real-time voice translation. Speak naturally in your language, heard instantly in theirs.',
  keywords: ['voice translation', 'real-time', 'multilingual', 'AI', 'speech recognition'],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className={inter.className}>
        {children}
        <Toaster
          position="top-right"
          toastOptions={{
            style: {
              background: '#161b22',
              color: '#fff',
              border: '1px solid #30363d',
              borderRadius: '12px',
            },
            success: { iconTheme: { primary: '#4c6ef5', secondary: '#fff' } },
          }}
        />
      </body>
    </html>
  );
}
