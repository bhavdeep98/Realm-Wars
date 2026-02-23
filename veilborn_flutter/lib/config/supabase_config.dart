class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qsexqntsuprxuyzssdda.supabase.co',
  );
  
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFzZXhxbnRzdXByeHV5enNzZGRhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDA0MjU5NzAsImV4cCI6MjA1NjAwMTk3MH0.Ks-LpL\$DwEnE\$#rs6',
  );

  // Edge Function URLs
  static const String resolveRoundUrl = '$url/functions/v1/resolve-round';
}
