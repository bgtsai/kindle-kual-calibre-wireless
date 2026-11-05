package zhconv

import "testing"

// Expected values are what longbridgeapp/opencc v0.3.13 produced (the package used up to
// v0.8.0), so book file names don't change with the switch.
func TestConvert(t *testing.T) {
	cases := []struct{ conv, in, want string }{
		{"s2tw", "游戏自控力：游戏高手也可以是学习能手 - 董祁奇", "遊戲自控力：遊戲高手也可以是學習能手 - 董祁奇"},
		{"s2tw", "余留事务汇总抛摆四克", "餘留事務匯總拋擺四克"},
		{"s2tw", "头发与发展 鼠标", "頭髮與發展 鼠標"},
		{"s2tw", "Harry Potter (2)", "Harry Potter (2)"},
		{"tw2s", "遊戲自控力：遊戲高手也可以是學習能手", "游戏自控力：游戏高手也可以是学习能手"},
		{"tw2s", "顯著 著名", "显著 著名"},
	}
	for _, c := range cases {
		cv, err := New(c.conv)
		if err != nil {
			t.Fatal(err)
		}
		if got, _ := cv.Convert(c.in); got != c.want {
			t.Errorf("%s(%q) = %q, want %q", c.conv, c.in, got, c.want)
		}
	}
}
