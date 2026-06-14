import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatTime(date: Date): string {
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

export function getLanguageName(code: string): string {
  const names: Record<string, string> = {
    en: 'English', es: 'Spanish', fr: 'French', de: 'German',
    it: 'Italian', pt: 'Portuguese', ru: 'Russian', zh: 'Chinese',
    ja: 'Japanese', ko: 'Korean', ar: 'Arabic', hi: 'Hindi',
    ur: 'Urdu', tr: 'Turkish', nl: 'Dutch', pl: 'Polish',
    sv: 'Swedish', no: 'Norwegian', da: 'Danish', fi: 'Finnish',
  };
  return names[code] || code.toUpperCase();
}

export function getLanguageFlag(code: string): string {
  const flags: Record<string, string> = {
    en: '🇺🇸', es: '🇪🇸', fr: '🇫🇷', de: '🇩🇪', it: '🇮🇹',
    pt: '🇧🇷', ru: '🇷🇺', zh: '🇨🇳', ja: '🇯🇵', ko: '🇰🇷',
    ar: '🇸🇦', hi: '🇮🇳', ur: '🇵🇰', tr: '🇹🇷', nl: '🇳🇱',
    pl: '🇵🇱', sv: '🇸🇪', no: '🇳🇴', da: '🇩🇰', fi: '🇫🇮',
  };
  return flags[code] || '🌐';
}
