p 'hello'

return if false
return '' unless true

class Hoge < Object
  # comment
  def plus(hoge, fuga)
    hoge + fuga
  end

  def minus(hoge, fuga)
    hoge - fuga
  end
end

'not use string'

42

hoge = Hoge.new

if hoge.plus(1, 2) > 3
  p '3'
else
  p hoge.plus(2, 3) + hoge.minus(5, 3)
end


p :"a-a"
