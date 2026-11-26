# 驗證失敗時，錯誤欄位要怎麼標示（spec §8）。
#
# 為什麼要改：Rails 預設會在出錯的欄位外面多包一層 <div class="field_with_errors">。
# 我們的表單用格線（grid／flex）排版，規定「格子裡那一格要撐滿」；多包一層之後，
# 撐滿的變成外面那層 div，裡面的輸入框縮回預設寬度，郵遞區號這種窄欄位就會凸出去。
#
# 改成：不包任何東西，直接在輸入框本身加紅框（看得出哪一格要改），
# 再加 aria-invalid="true"（讓螢幕閱讀器也知道這格有錯）。
# 欄位標籤（<label>）維持原樣，只處理輸入框、下拉選單、多行文字框。
Rails.application.config.action_view.field_error_proc = proc do |html_tag, _instance|
  fragment = Nokogiri::HTML::DocumentFragment.parse(html_tag)
  field = fragment.at_css("input, select, textarea")

  if field
    field["aria-invalid"] = "true"
    field["class"] = [field["class"], "border-red-500"].compact.join(" ")
    fragment.to_html.html_safe
  else
    html_tag
  end
end
