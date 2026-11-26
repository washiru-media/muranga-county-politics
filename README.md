# Murang'a County Politics

A Vercel + Supabase multi-category public opinion polling website.

## Included
- Responsive public polling UI and live result refresh.
- Categories and aspirants managed centrally by authenticated admins.
- Add/edit/deactivate aspirants and upload profile photos.
- Small circular profile photos.
- Server-side IP-based vote lock per category (HMAC-SHA256; raw IP is not stored).
- WhatsApp, Facebook and M-Pesa support popup.

## 1. Create/configure Supabase
1. Create a Supabase project.
2. Open SQL Editor and run `supabase/schema.sql`.
3. In Authentication > Users, create an admin user (email/password).
4. Copy that user's UUID. Run:
   ```sql
   insert into public.admin_users(user_id) values ('YOUR-AUTH-USER-UUID');
   ```
5. Copy the Project URL and anon/public key from Project Settings > API.
6. Add at least one category from the website admin dashboard after signing in.

## 2. Configure the website
In `index.html`, replace:
- `YOUR_SUPABASE_PROJECT_URL`
- `YOUR_SUPABASE_ANON_KEY`
- `https://www.facebook.com/YOUR_PAGE_USERNAME` with the real Facebook page URL.

## 3. Deploy to Vercel
Import this folder/repository into Vercel. Set these Environment Variables:
- `SUPABASE_URL` = Supabase project URL
- `SUPABASE_SERVICE_ROLE_KEY` = Supabase service-role key (server-side only; NEVER put this in index.html)
- `IP_HASH_SECRET` = a long random secret (32+ random bytes; keep private)

Install dependencies and deploy. Vercel will serve `index.html` and `/api/vote`.

## Important IP-lock notes
- The restriction is one vote per category per IP address. A household, office, school, mobile carrier or public Wi-Fi sharing one public IP may share the same vote allowance.
- VPNs, mobile network IP changes, proxies and IPv6 address rotation can affect IP-only enforcement. IP locking is a deterrent, not proof of a unique human voter.
- The raw IP is not stored in the database; only a keyed HMAC hash is stored. Configure a suitable privacy notice/policy for your jurisdiction and disclose the IP-based anti-abuse processing.
- Admin sign-in uses Supabase Auth. Only UUIDs inserted into `admin_users` receive admin privileges.
- Deleting a category permanently deletes its aspirants, votes and IP locks due to foreign-key cascade. Deleting an aspirant in the dashboard deactivates it so historical votes remain.

## Important launch checks
- Add the actual Facebook page URL.
- Set all three Vercel environment variables.
- Add your first admin UUID to `admin_users`.
- Test voting from two different network IPs and test the duplicate-vote rejection.
- Keep the Supabase service-role key exclusively in Vercel environment variables.
