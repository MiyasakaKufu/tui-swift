/^        \/\/ H11 の計測。製品には含めない。$/ { skip = 1; next }
skip && /^        \),$/ { skip = 0; next }
skip { next }
{ print }
