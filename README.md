# NOVA AI

Android-এর জন্য Personal Phone Agent: বাংলা ও ইংরেজি ভয়েসে ফোন চালায়। Paid API লাগে না, root লাগে না, অফলাইনেও কাজ করতে পারে।

## Build

GitHub Actions (`.github/workflows/build-apk.yml`) debug APK বানায়। `main`-এ push করলে বা Actions ট্যাব থেকে হাতে চালালে `nova-ai-debug-apk` নামে APK পাওয়া যায়।

## Project layout

- `app/src/main/java/com/nova/ai/` : Kotlin কোড, প্রতিটি মডিউল আলাদা প্যাকেজে (voice, nlp, apps, accessibility ইত্যাদি)।
- `setup-*.sh` : প্রতিটি ফেজের ইনস্টল স্ক্রিপ্ট। রিপো রুট থেকে চালাতে হয়।

## Rules

1. কোনো ফিচার বাদ যাবে না, শুধু যোগ হবে।
2. কোড প্রফেশনাল হবে: টাইপড ভ্যারিয়েবল, এরর হ্যান্ডলিং, কমেন্ট।
3. প্রতিটি ফেজ শেষে commit এবং APK টেস্ট।
