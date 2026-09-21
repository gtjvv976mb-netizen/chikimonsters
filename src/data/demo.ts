// Demo data standing in for the database until one is connected.
// Shapes mirror src/data/schema.sql so swapping in real queries is a
// change of source, not a change of every component.
//
// These are invented clinics and invented patients. No real person's
// health information belongs in a repository.

export type ToothCondition =
  | 'sound' | 'caries' | 'filled' | 'crown' | 'bridge' | 'implant'
  | 'root_canal' | 'sealant' | 'veneer' | 'missing' | 'unerupted' | 'impacted';

export type Notation = 'fdi' | 'universal' | 'palmer';

export type Surface = 'mesial' | 'distal' | 'buccal' | 'lingual' | 'occlusal';

/** A finding on one tooth. Surface-scoped conditions carry the surfaces they
 *  affect; whole-tooth conditions do not, because "missing, mesial" is not a
 *  thing a dentist can say. */
export interface ToothMark {
  condition: ToothCondition;
  surfaces?: Surface[];
}

/** Which conditions are recorded per surface and which apply to the whole
 *  tooth. Drives the palette: picking "missing" disables the surface row. */
export const SURFACE_SCOPED: ToothCondition[] = ['caries', 'filled', 'sealant'];

export const SURFACE_LABEL: Record<Surface, string> = {
  mesial: 'Mesial',
  distal: 'Distal',
  buccal: 'Buccal',
  lingual: 'Lingual',
  occlusal: 'Occlusal',
};

/** Short forms staff actually write in notes: MOD, DB, and so on. */
export const SURFACE_CODE: Record<Surface, string> = {
  mesial: 'M', distal: 'D', buccal: 'B', lingual: 'L', occlusal: 'O',
};

/** Anteriors have an incisal edge, not an occlusal table. Same slot, different
 *  word, and using the wrong one in a clinical note is an error. */
export const isAnterior = (fdi: number) => fdi % 10 <= 3;
export const occlusalWord = (fdi: number) => (isAnterior(fdi) ? 'Incisal' : 'Occlusal');
export const occlusalCode = (fdi: number) => (isAnterior(fdi) ? 'I' : 'O');

export const surfaceSummary = (fdi: number, s?: Surface[]) =>
  !s || s.length === 0
    ? ''
    : (['mesial', 'occlusal', 'distal', 'buccal', 'lingual'] as Surface[])
        .filter((x) => s.includes(x))
        .map((x) => (x === 'occlusal' ? occlusalCode(fdi) : SURFACE_CODE[x]))
        .join('');

export interface Clinic {
  slug: string;
  name: string;
  group: string;
  city: string;
  province: string;
  notation: Notation;
  tin: string | null;
  chairs: number;
}

export interface Patient {
  id: string;
  clinic: string;
  chartNo: string;
  firstName: string;
  lastName: string;
  birthDate: string;
  sex: 'female' | 'male' | 'other' | 'undisclosed';
  phone: string;
  allergies: string[];
  conditions: string[];
  lastVisit: string;
  balance: number;
  teeth: Partial<Record<number, ToothMark>>;
}

export interface Appointment {
  id: string;
  clinic: string;
  patientId: string;
  startsAt: string;
  reason: string;
  status: 'booked' | 'confirmed' | 'arrived' | 'in_lobby' | 'in_chair' | 'completed' | 'no_show' | 'cancelled';
}

export interface Claim {
  id: string;
  clinic: string;
  patientId: string;
  provider: string;
  claimed: number;
  approved: number | null;
  status: 'draft' | 'filed' | 'approved' | 'partly_approved' | 'denied' | 'paid';
  filedAt: string | null;
}

export const clinics: Clinic[] = [
  {
    slug: 'session-road',
    name: 'Session Road Dental',
    group: 'Highland Dental Group',
    city: 'Baguio City',
    province: 'Benguet',
    notation: 'fdi',
    tin: '009-123-456-000',
    chairs: 4,
  },
  {
    slug: 'marikina-heights',
    name: 'Marikina Heights Dental',
    group: 'Highland Dental Group',
    city: 'Marikina City',
    province: 'Metro Manila',
    notation: 'fdi',
    tin: null,
    chairs: 2,
  },
];

export const patients: Patient[] = [
  {
    id: 'p1', clinic: 'session-road', chartNo: 'SR-0142',
    firstName: 'Maria Liza', lastName: 'Dela Cruz',
    birthDate: '1988-03-14', sex: 'female', phone: '+63 917 555 0142',
    allergies: ['Penicillin'], conditions: ['Hypertension'],
    lastVisit: '2026-08-28', balance: 2400,
    teeth: {
      16: { condition: 'filled', surfaces: ['occlusal'] },
      26: { condition: 'caries', surfaces: ['mesial', 'occlusal'] },
      36: { condition: 'crown' },
      46: { condition: 'root_canal' },
      18: { condition: 'missing' },
      28: { condition: 'missing' },
    },
  },
  {
    id: 'p2', clinic: 'session-road', chartNo: 'SR-0143',
    firstName: 'Joel', lastName: 'Bautista',
    birthDate: '1975-11-02', sex: 'male', phone: '+63 918 555 0143',
    allergies: [], conditions: ['Type 2 diabetes'],
    lastVisit: '2026-09-11', balance: 0,
    teeth: {
      11: { condition: 'veneer' },
      21: { condition: 'veneer' },
      37: { condition: 'filled', surfaces: ['mesial', 'occlusal', 'distal'] },
      47: { condition: 'caries', surfaces: ['distal'] },
    },
  },
  {
    id: 'p3', clinic: 'session-road', chartNo: 'SR-0144',
    firstName: 'Anna Patricia', lastName: 'Reyes',
    birthDate: '2014-06-21', sex: 'female', phone: '+63 920 555 0144',
    allergies: ['Latex'], conditions: [],
    lastVisit: '2026-09-18', balance: 850,
    teeth: {
      16: { condition: 'sealant', surfaces: ['occlusal'] },
      26: { condition: 'sealant', surfaces: ['occlusal'] },
      36: { condition: 'sealant', surfaces: ['occlusal'] },
      46: { condition: 'sealant', surfaces: ['occlusal'] },
    },
  },
  {
    id: 'p4', clinic: 'marikina-heights', chartNo: 'MH-0031',
    firstName: 'Rogelio', lastName: 'Santos',
    birthDate: '1962-01-09', sex: 'male', phone: '+63 927 555 0031',
    allergies: [], conditions: ['On anticoagulants'],
    lastVisit: '2026-09-02', balance: 12750,
    teeth: {
      14: { condition: 'implant' },
      15: { condition: 'bridge' },
      16: { condition: 'bridge' },
      24: { condition: 'missing' },
      34: { condition: 'filled', surfaces: ['buccal'] },
    },
  },
];

export const appointments: Appointment[] = [
  { id: 'a1', clinic: 'session-road', patientId: 'p1', startsAt: '2026-09-21T09:00:00+08:00', reason: 'Restoration 26', status: 'in_chair' },
  { id: 'a2', clinic: 'session-road', patientId: 'p3', startsAt: '2026-09-21T09:30:00+08:00', reason: 'Prophylaxis', status: 'in_lobby' },
  { id: 'a3', clinic: 'session-road', patientId: 'p2', startsAt: '2026-09-21T10:15:00+08:00', reason: 'Recall check', status: 'confirmed' },
  { id: 'a4', clinic: 'marikina-heights', patientId: 'p4', startsAt: '2026-09-21T11:00:00+08:00', reason: 'Bridge fitting', status: 'booked' },
];

export const claims: Claim[] = [
  { id: 'c1', clinic: 'session-road', patientId: 'p1', provider: 'Maxicare', claimed: 4500, approved: 4500, status: 'paid', filedAt: '2026-07-02' },
  { id: 'c2', clinic: 'session-road', patientId: 'p2', provider: 'Intellicare', claimed: 8200, approved: null, status: 'filed', filedAt: '2026-06-30' },
  { id: 'c3', clinic: 'session-road', patientId: 'p3', provider: 'Medicard', claimed: 1800, approved: 900, status: 'partly_approved', filedAt: '2026-08-15' },
  { id: 'c4', clinic: 'marikina-heights', patientId: 'p4', provider: 'Maxicare', claimed: 22000, approved: null, status: 'filed', filedAt: '2026-05-20' },
];

export const CONDITION_LABEL: Record<ToothCondition, string> = {
  sound: 'Sound', caries: 'Caries', filled: 'Filled', crown: 'Crown',
  bridge: 'Bridge', implant: 'Implant', root_canal: 'Root canal',
  sealant: 'Sealant', veneer: 'Veneer', missing: 'Missing',
  unerupted: 'Unerupted', impacted: 'Impacted',
};

export const peso = (n: number) =>
  new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP', maximumFractionDigits: 0 }).format(n);

export const clinicBySlug = (slug: string) => clinics.find((c) => c.slug === slug);
export const patientsOf = (slug: string) => patients.filter((p) => p.clinic === slug);
export const appointmentsOf = (slug: string) => appointments.filter((a) => a.clinic === slug);
export const claimsOf = (slug: string) => claims.filter((c) => c.clinic === slug);
export const patientById = (id: string) => patients.find((p) => p.id === id);

// Days a filed claim has been waiting. The number clinics cannot see anywhere
// else, and the reason money goes missing for a quarter at a time.
export const daysWaiting = (filedAt: string | null, today = new Date('2026-09-21')) =>
  filedAt ? Math.round((today.getTime() - new Date(filedAt).getTime()) / 86_400_000) : 0;
