# 🎯 Olist Project — SQL Status & Aage Ka Detailed Roadmap

## ✅ SQL Kaam — 100% COMPLETE HAI!

Aapke **6 SQL files** ne poore roadmap ke saare phases cover kar liye hain:

| File | Phase | Status |
| :--- | :--- | :---: |
| `01_schema_setup.sql` | Schema + Tables + Foreign Keys | ✅ Done |
| `02_data_import.sql` | CSV Import + Row Count Audit View | ✅ Done |
| `03_data_quality.sql` | Indexes + Duplicate Checks + Date Sanity | ✅ Done |
| `04_eda_kpis_logistics.sql` | Business KPIs, MoM Growth, Delivery Analysis | ✅ Done |
| `05_advanced_cohort_rfm.sql` | Cohort Retention, RFM, Seller Pareto 80/20 | ✅ Done |
| `06_production_views.sql` | Production Views + Final Indexes | ✅ Done |

> [!IMPORTANT]
> SQL kaam poora ho gaya hai. Ab **Python → Power BI** sequence follow karo.
> Project timeline ke hisaab se aap **Week 2 (Python)** par hain.

---

## 📅 WEEK 2: Python Analysis (3–4 Din)

### 🗂️ Folder: `Python/`
Aapka `Python/.gitkeep` folder already exist karta hai — wahan 3 notebooks banani hain.

---

### 📓 Notebook 1: `01_data_cleaning_eda.ipynb`

**Goal**: Data load karo, clean karo, aur samjho.

#### Step 1 — Setup & Imports
```python
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import warnings
warnings.filterwarnings('ignore')

# Sabhi 8 CSV files load karo
orders       = pd.read_csv('../Data/olist_orders_dataset.csv', parse_dates=[
                   'order_purchase_timestamp','order_approved_at',
                   'order_delivered_carrier_date','order_delivered_customer_date',
                   'order_estimated_delivery_date'])
customers    = pd.read_csv('../Data/olist_customers_dataset.csv')
order_items  = pd.read_csv('../Data/olist_order_items_dataset.csv')
payments     = pd.read_csv('../Data/olist_order_payments_dataset.csv')
reviews      = pd.read_csv('../Data/olist_order_reviews_dataset.csv')
products     = pd.read_csv('../Data/olist_products_dataset.csv')
sellers      = pd.read_csv('../Data/olist_sellers_dataset.csv')
translation  = pd.read_csv('../Data/product_category_name_translation.csv')

print("Data loaded!")
```

#### Step 2 — Missing Values Check
```python
# Sabhi dataframes mein missing values dekho
for name, df in [('orders', orders), ('customers', customers),
                  ('order_items', order_items), ('payments', payments),
                  ('reviews', reviews), ('products', products)]:
    missing = df.isnull().sum()
    if missing.any():
        print(f"\n--- {name} ---")
        print(missing[missing > 0])
```

#### Step 3 — Computed Columns Banao
```python
# Delivered orders filter karo
delivered = orders[orders['order_status'] == 'delivered'].copy()

# Delivery duration calculate karo
delivered['delivery_days'] = (
    delivered['order_delivered_customer_date'] -
    delivered['order_purchase_timestamp']
).dt.days

# Delay flag lagao
delivered['is_delayed'] = (
    delivered['order_delivered_customer_date'] >
    delivered['order_estimated_delivery_date']
)

# Month column add karo
delivered['order_month'] = delivered['order_purchase_timestamp'].dt.to_period('M')
```

#### Step 4 — EDA Visualizations (Yeh banao zaroor!)

**Chart 1: Monthly Orders Trend**
```python
monthly = delivered.groupby('order_month')['order_id'].count().reset_index()
monthly.columns = ['month', 'order_count']

plt.figure(figsize=(14, 5))
plt.plot(monthly['month'].astype(str), monthly['order_count'], marker='o', color='#2196F3')
plt.xticks(rotation=45)
plt.title('Monthly Order Volume (2016–2018)', fontsize=14, fontweight='bold')
plt.xlabel('Month')
plt.ylabel('Number of Orders')
plt.tight_layout()
plt.savefig('monthly_orders.png', dpi=150)
plt.show()
```

**Chart 2: Delivery Days Distribution**
```python
plt.figure(figsize=(10, 5))
sns.histplot(delivered['delivery_days'].dropna(), bins=40, kde=True, color='#4CAF50')
plt.axvline(delivered['delivery_days'].mean(), color='red', linestyle='--',
            label=f"Mean: {delivered['delivery_days'].mean():.1f} days")
plt.title('Delivery Time Distribution', fontsize=14, fontweight='bold')
plt.xlabel('Days to Deliver')
plt.legend()
plt.tight_layout()
plt.savefig('delivery_distribution.png', dpi=150)
plt.show()
```

**Chart 3: Heatmap — Orders by Day of Week & Hour**
```python
orders['dow'] = orders['order_purchase_timestamp'].dt.day_name()
orders['hour'] = orders['order_purchase_timestamp'].dt.hour

heatmap_data = orders.groupby(['dow', 'hour'])['order_id'].count().unstack()
day_order = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday']
heatmap_data = heatmap_data.reindex(day_order)

plt.figure(figsize=(16, 5))
sns.heatmap(heatmap_data, cmap='YlOrRd', linewidths=0.3)
plt.title('Order Volume Heatmap: Day of Week vs Hour of Day', fontsize=14, fontweight='bold')
plt.tight_layout()
plt.savefig('heatmap_orders.png', dpi=150)
plt.show()
```

**Chart 4: Top 10 Product Categories**
```python
# Merge aur English names lao
items_prod = order_items.merge(products[['product_id','product_category_name']], on='product_id')
items_prod = items_prod.merge(translation, on='product_category_name', how='left')
items_prod['category_en'] = items_prod['product_category_name_english'].fillna(
                             items_prod['product_category_name'])

top_cats = items_prod.groupby('category_en')['price'].sum().nlargest(10).reset_index()

plt.figure(figsize=(10, 6))
sns.barplot(x='price', y='category_en', data=top_cats, palette='Blues_r')
plt.title('Top 10 Product Categories by Revenue', fontsize=14, fontweight='bold')
plt.xlabel('Total Revenue (BRL)')
plt.ylabel('')
plt.tight_layout()
plt.savefig('top_categories.png', dpi=150)
plt.show()
```

---

### 📓 Notebook 2: `02_rfm_customer_segments.ipynb`

**Goal**: Python mein RFM segmentation (SQL se different — visualization + export ke liye).

```python
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Data load karo
orders    = pd.read_csv('../Data/olist_orders_dataset.csv',
                        parse_dates=['order_purchase_timestamp'])
customers = pd.read_csv('../Data/olist_customers_dataset.csv')
payments  = pd.read_csv('../Data/olist_order_payments_dataset.csv')

# Delivered orders + unique customer join
delivered = orders[orders['order_status'] == 'delivered']
df = delivered.merge(customers[['customer_id','customer_unique_id']], on='customer_id')
df = df.merge(payments.groupby('order_id')['payment_value'].sum().reset_index(),
              on='order_id')

# Reference date = dataset ki max date
ref_date = df['order_purchase_timestamp'].max()

# RFM compute karo
rfm = df.groupby('customer_unique_id').agg(
    recency   = ('order_purchase_timestamp', lambda x: (ref_date - x.max()).days),
    frequency = ('order_id', 'nunique'),
    monetary  = ('payment_value', 'sum')
).reset_index()

rfm['monetary'] = rfm['monetary'].round(2)

# Scoring — same logic as SQL
rfm['r_score'] = pd.qcut(rfm['recency'].rank(method='first'),
                          q=4, labels=[4, 3, 2, 1]).astype(int)
rfm['f_score'] = rfm['frequency'].apply(lambda x: 4 if x > 1 else 1)
rfm['m_score'] = pd.qcut(rfm['monetary'].rank(method='first'),
                          q=4, labels=[1, 2, 3, 4]).astype(int)

rfm['rfm_code'] = rfm['r_score'].astype(str) + rfm['f_score'].astype(str) + rfm['m_score'].astype(str)

# Segments assign karo
def assign_segment(row):
    r, f, m = row['r_score'], row['f_score'], row['m_score']
    if r >= 3 and f == 4 and m >= 3: return 'Champions'
    elif r >= 3 and f == 4:           return 'Loyal Customers'
    elif r == 2 and f == 4:           return 'Needs Attention (Repeat)'
    elif r == 1 and f == 4:           return 'Cant Lose Them (At Risk)'
    elif r >= 3 and f == 1 and m >= 3: return 'Promising High-Spenders'
    elif r == 1 and m == 1:           return 'Lost / Churned'
    else:                             return 'Standard One-Time Buyers'

rfm['customer_segment'] = rfm.apply(assign_segment, axis=1)

# Segment summary
seg_summary = rfm.groupby('customer_segment').agg(
    customer_count = ('customer_unique_id', 'count'),
    avg_spend      = ('monetary', 'mean'),
    total_revenue  = ('monetary', 'sum')
).sort_values('total_revenue', ascending=False).reset_index()

print(seg_summary)

# Visualization — Segment Distribution
plt.figure(figsize=(10, 5))
sns.barplot(x='customer_count', y='customer_segment', data=seg_summary, palette='coolwarm')
plt.title('Customer Segments by Count (RFM)', fontsize=14, fontweight='bold')
plt.xlabel('Number of Customers')
plt.tight_layout()
plt.savefig('rfm_segments.png', dpi=150)
plt.show()

# Export CSV (Power BI ke liye)
rfm.to_csv('../Data/rfm_output.csv', index=False)
print("rfm_output.csv saved!")
```

---

### 📓 Notebook 3: `03_hypothesis_testing.ipynb`

**Goal**: Statistically PROVE karo ki delivery delay review score girata hai.

```python
import pandas as pd
import numpy as np
from scipy import stats
import matplotlib.pyplot as plt
import seaborn as sns

# Data load karo
orders  = pd.read_csv('../Data/olist_orders_dataset.csv',
                      parse_dates=['order_delivered_customer_date',
                                   'order_estimated_delivery_date'])
reviews = pd.read_csv('../Data/olist_order_reviews_dataset.csv')

# Merge aur filter
df = orders[orders['order_status'] == 'delivered'].merge(
         reviews[['order_id','review_score']], on='order_id')

df['is_delayed'] = (
    df['order_delivered_customer_date'] > df['order_estimated_delivery_date']
)

# --- T-Test ---
delayed = df[df['is_delayed'] == True]['review_score'].dropna()
ontime  = df[df['is_delayed'] == False]['review_score'].dropna()

t_stat, p_value = stats.ttest_ind(delayed, ontime, equal_var=False)

print("=" * 45)
print("TWO-SAMPLE T-TEST RESULTS")
print("=" * 45)
print(f"Delayed Orders  — Mean Score: {delayed.mean():.3f} (n={len(delayed):,})")
print(f"On-Time Orders  — Mean Score: {ontime.mean():.3f} (n={len(ontime):,})")
print(f"T-Statistic    : {t_stat:.4f}")
print(f"P-Value        : {p_value:.2e}")
if p_value < 0.05:
    print("\n✅ REJECT H₀: Delivery delay SIGNIFICANTLY lowers review scores! (p < 0.05)")
else:
    print("\n❌ FAIL TO REJECT H₀")

# Box Plot
plt.figure(figsize=(8, 5))
sns.boxplot(x='is_delayed', y='review_score', data=df,
            palette={True: '#f44336', False: '#4CAF50'})
plt.xticks([0, 1], ['On-Time / Early', 'Delayed'])
plt.title(f'Review Score: On-Time vs Delayed (p = {p_value:.2e})',
          fontsize=13, fontweight='bold')
plt.ylabel('Review Score (1–5)')
plt.tight_layout()
plt.savefig('hypothesis_test.png', dpi=150)
plt.show()
```

---

## 📅 WEEK 3–4: Power BI Dashboard (3–5 Din)

### 🗂️ Folder: `Power BI/`

### Step 1 — Data Sources Connect karo (2 Tarike)

**Option A (Recommended) — MySQL Direct Connect:**
- Power BI Desktop → Get Data → MySQL Database
- Server: `localhost`, Database: `olist`
- Inhe import karo:
  - `vw_order_master`
  - `vw_order_item_details`
  - `vw_rfm_customer_segments`
  - `vw_monthly_revenue_growth`
  - `vw_state_revenue`
  - `vw_delivery_by_state`
  - `vw_payment_breakdown`
  - `vw_cohort_retention`
  - `vw_seller_pareto`

**Option B — CSV Files (Agar MySQL connect na ho):**
- Python notebook se cleaned CSVs export karo aur woh Power BI mein load karo.

---

### Step 2 — Star Schema Data Model Banao

Power BI mein **Model View** mein yeh relationships set karo:

```
Fact_Orders (vw_order_master)
    ├── Dim_Date (order_purchase_timestamp)
    ├── Dim_Customer (customer_unique_id)
    └── Dim_State (customer_state)

Fact_Items (vw_order_item_details)
    ├── Dim_Product (product_id / category_english)
    └── Dim_Seller (seller_id / seller_state)
```

> [!TIP]
> **Dim_Date Table** khud banao: New Table → `Dim_Date = CALENDARAUTO()` aur usme Month, Year, Quarter columns add karo.

---

### Step 3 — DAX Measures (New Measure mein likho)

```dax
// === CORE KPIs ===
Total Revenue = SUM(vw_order_item_details[price])
Total Freight = SUM(vw_order_item_details[freight_value])
Total Orders  = DISTINCTCOUNT(vw_order_master[order_id])
AOV           = DIVIDE([Total Revenue], [Total Orders], 0)

// === DELIVERY ===
Delayed Orders =
CALCULATE([Total Orders],
    vw_order_master[is_delivery_delayed] = 1)

Late Delivery % =
DIVIDE([Delayed Orders], [Total Orders], 0) * 100

Avg Delivery Days = AVERAGE(vw_order_master[delivery_days])

// === REVIEWS ===
Avg Review Score = AVERAGE(vw_order_master[review_score])

Pct 1-Star Reviews =
DIVIDE(
    COUNTROWS(FILTER(vw_order_master, vw_order_master[review_score] = 1)),
    [Total Orders], 0) * 100

// === MoM GROWTH ===
Revenue LM =
CALCULATE([Total Revenue],
    DATEADD(Dim_Date[Date], -1, MONTH))

MoM Growth % =
DIVIDE([Total Revenue] - [Revenue LM], [Revenue LM], 0) * 100
```

---

### Step 4 — 3-Page Dashboard Build

#### 📄 Page 1: Sales Executive Overview
| Visual | Type | Data |
| :--- | :--- | :--- |
| Total Revenue | KPI Card | `Total Revenue` measure |
| Total Orders | KPI Card | `Total Orders` measure |
| AOV | KPI Card | `AOV` measure |
| Avg Review Score | KPI Card | `Avg Review Score` measure |
| Monthly Revenue Trend | Line Chart | month → revenue + MoM% |
| Top 10 Categories | Horizontal Bar | category_english → revenue |
| Payment Split | Donut Chart | payment_type → payment_value |
| **Slicers** | Year, Category, Order Status | — |

#### 📄 Page 2: Customer & Geography
| Visual | Type | Data |
| :--- | :--- | :--- |
| Brazil State Map | Filled Map | customer_state → revenue |
| RFM Segments | Bar Chart | customer_segment → count |
| Top States Table | Matrix | state, orders, revenue, freight |
| Freight vs Delivery Scatter | Scatter Plot | avg_freight → avg_delivery_days |
| Repeat Customers | KPI Card | `3%` repeat rate insight |

#### 📄 Page 3: Logistics & Satisfaction
| Visual | Type | Data |
| :--- | :--- | :--- |
| Avg Delivery Days | KPI Card | `Avg Delivery Days` |
| On-Time Rate % | KPI Card | `100 - Late Delivery %` |
| 1-Star Reviews % | KPI Card | `Pct 1-Star Reviews` |
| Delay vs Review | Dual-Axis Line | month → delay_rate + avg_review |
| State Delay Heatmap | Matrix | state → delay_rate_pct |
| Top Delayed States | Bar Chart | state → delayed_orders |

---

### Step 5 — Design Tips (Dashboard Polish)

- **Color Palette**: `#2196F3` (Blue - primary), `#4CAF50` (Green - good), `#f44336` (Red - alert)
- **Font**: Segoe UI, 12pt for labels, 20pt+ for KPI cards
- **Background**: Light grey (#F5F5F5) ya white
- **Title Banner**: Company logo placeholder + "Olist E-Commerce Analysis | {Current Year}"
- **Mobile Layout**: Page 3 ko phone view mein bhi optimize karo (View → Mobile Layout)

---

## 📁 Final Folder Structure (Jab Poora Ho Jaye)

```text
ecommerce-sales-analysis/
├── README.md                          ← GitHub showcase (screenshots + findings)
├── Data/
│   ├── olist_*_dataset.csv            ← Raw CSVs (gitignore ya zip karke rakho)
│   └── rfm_output.csv                 ← Python RFM export (Power BI ke liye)
├── Sql/
│   ├── 01_schema_setup.sql            ✅ Done
│   ├── 02_data_import.sql             ✅ Done
│   ├── 03_data_quality.sql            ✅ Done
│   ├── 04_eda_kpis_logistics.sql      ✅ Done
│   ├── 05_advanced_cohort_rfm.sql     ✅ Done
│   └── 06_production_views.sql        ✅ Done
├── Python/
│   ├── 01_data_cleaning_eda.ipynb     ← Week 2, Din 1-2
│   ├── 02_rfm_customer_segments.ipynb ← Week 2, Din 3
│   └── 03_hypothesis_testing.ipynb    ← Week 2, Din 4
├── Excel/
│   └── olist_executive_summary.xlsx   ← Optional (Week 3)
├── Power BI/
│   ├── olist_sales_analytics.pbix     ← Week 3-4
│   └── screenshots/                   ← Dashboard images for README
└── Docs/
    ├── olist_sql_analysis_roadmap.md  ✅ Exists
    └── ecommerce_olist_roadmap.md     ✅ Exists
```

---

## 🔢 Aage Ka Order (Step-by-Step)

```
1. ✅ SQL (Done!)
           ↓
2. 🐍 Python Notebook 1 — EDA & Cleaning (1-2 din)
           ↓
3. 🐍 Python Notebook 2 — RFM Segmentation (1 din)
           ↓
4. 🐍 Python Notebook 3 — Hypothesis Testing (1 din)
           ↓
5. 📊 Power BI — Data Import + Star Schema (1 din)
           ↓
6. 📊 Power BI — DAX Measures (1 din)
           ↓
7. 📊 Power BI — 3-Page Dashboard Design (2-3 din)
           ↓
8. 📝 GitHub README Update + Screenshots (1 din)
           ↓
9. 🚀 LinkedIn Post + Portfolio Done!
```

> [!NOTE]
> Excel step optional hai — agar time tight ho toh skip karo, SQL + Python + Power BI kaafi hai portfolio ke liye.
