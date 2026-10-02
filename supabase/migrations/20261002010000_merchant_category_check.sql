-- Catégories marchand : même référentiel que lib/models/merchant_category.dart
alter table public.merchant_requests
  drop constraint if exists merchant_requests_category_check;
alter table public.merchant_requests
  add constraint merchant_requests_category_check check (category in (
    'groceries', 'restaurant', 'cafe', 'shopping', 'fashion', 'electronics',
    'beauty', 'health', 'transport', 'fuel', 'housing', 'utilities',
    'telecom', 'education', 'entertainment', 'sports', 'travel', 'services',
    'online', 'other'
  ));
