export type AuthContext = {
  userId: string;
  requestId: string;
  authProvider: 'dev' | 'supabase';
  email: string | null;
  isAdmin: boolean;
};
