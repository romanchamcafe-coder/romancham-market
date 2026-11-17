# Romancham Market

Online store for **Romancham** café, Anna Nagar, Chennai — craft chocolates, coffee beans, gift hampers, festive and corporate gifting.

Live: https://romanchammarket.com · Admin: https://romanchammarket.com/admin

## How it works

| Piece | What it does |
|---|---|
| `index.html` | Storefront — products, search/filter, product details, cart, hamper builder, checkout, pincode check, newsletter, corporate enquiry, WhatsApp |
| `admin.html` | Admin panel (Supabase login, admins only) — dashboard, orders, products + images, inventory, customers, enquiries, newsletter, pincodes, hamper boxes, settings |
| `policies.html` | Shipping / refund / privacy / terms (draft — review before relying on it) |
| `config.js` | Supabase URL + **anon (public)** key only |
| `supabase/schema.sql` | Database: tables, Row Level Security, order/stock functions, sample seed data |
| `vercel.json` | Clean URLs + security headers |

Hosting: **Vercel** (separate project from the café management app). Database/auth/storage: **Supabase** project `romancham-market` (separate from the café's `romancham` project).

## Security model
- Prices, totals, delivery charge and stock are computed **in the database** (`place_order` function) — the browser cannot change them.
- Public visitors can only read active products/settings, insert corporate enquiries, and call `place_order` / `subscribe_newsletter`. Orders, customers and subscribers are readable only by admins.
- The Supabase **service_role** key is never used in this site.

## Admin users
1. Supabase → Authentication → Users → **Add user** (email + password, auto-confirm).
2. SQL Editor: `insert into admins(user_id, email) select id, email from auth.users where email = 'you@example.com';`

## Orders today
Customer places order → saved as **Pending** with stock reserved → customer sends it to WhatsApp → you confirm & collect payment → mark **Paid / Confirmed** in admin. Cancelling returns stock.

## Next
- Razorpay online payment (needs Razorpay key id + secret → a small Vercel/Supabase Edge function verifies the signature before marking paid)
- Real product photos, prices, GSTIN/FSSAI, WhatsApp number (Admin → Settings / Products)
- Email notifications
