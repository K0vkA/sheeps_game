require 'gosu'
require_relative 'main'    
require_relative 'main2'   

WINDOW_WIDTH = 1000
WINDOW_HEIGHT = 600

class MenuWindow < Gosu::Window
  def initialize
    super WINDOW_WIDTH, WINDOW_HEIGHT
    self.caption = "Sheeps"

    @vid_image = Gosu::Image.new("vid.png")
    @background = Gosu::Image.new("shmenu.png")
    @btn1_img = Gosu::Image.new("sam.png")
    @btn2_img = Gosu::Image.new("dogon.png")

    @font_big = Gosu::Font.new(230, bold: true)
    @font_title = Gosu::Font.new(48, bold: true)

    @start_time = Gosu.milliseconds
    @show_intro = true
  end

  def update
    if @show_intro && Gosu.milliseconds - @start_time > 2000
      @show_intro = false
    end
  end

  def draw
    if @show_intro
      @vid_image.draw(0, 0, 0, WINDOW_WIDTH.to_f / @vid_image.width, WINDOW_HEIGHT.to_f / @vid_image.height)
      @font_big.draw_text_rel("SHEEPS!", WINDOW_WIDTH/2, WINDOW_HEIGHT/2, 1, 0.5, 0.5, 1.0, 1.0, Gosu::Color::YELLOW)
    else
      @background.draw(0, 0, 0, WINDOW_WIDTH.to_f / @background.width, WINDOW_HEIGHT.to_f / @background.height)
      @font_title.draw_text_rel("Выбери режим игры:", WINDOW_WIDTH/2, 60, 1, 0.5, 0.5, 1.0, 1.0, Gosu::Color::YELLOW)

      @btn1_img.draw(WINDOW_WIDTH/2 - 250, WINDOW_HEIGHT/2 - 100, 1, 0.5, 0.5)
      @btn2_img.draw(WINDOW_WIDTH/2 + 50, WINDOW_HEIGHT/2 - 100, 1, 0.5, 0.5)

      @font_title.draw_text_rel("Сам за себя", WINDOW_WIDTH/2 - 150, WINDOW_HEIGHT/2 + 120, 1, 0.5, 0.5, 1.0, 1.0, Gosu::Color::YELLOW)
      @font_title.draw_text_rel("Догонялки", WINDOW_WIDTH/2 + 150, WINDOW_HEIGHT/2 + 120, 1, 0.5, 0.5, 1.0, 1.0, Gosu::Color::YELLOW)
    end
  end

  def button_down(id)
    case id
    when Gosu::MS_LEFT
      unless @show_intro
        mx, my = mouse_x, mouse_y
        
        # Первая кнопка - "Сам за себя"
        if mx >= WINDOW_WIDTH/2 - 250 && mx <= WINDOW_WIDTH/2 - 250 + @btn1_img.width*0.5 &&
           my >= WINDOW_HEIGHT/2 - 100 && my <= WINDOW_HEIGHT/2 - 100 + @btn1_img.height*0.5
          close
          GameWindow1.new.show
        end

        # Вторая кнопка - "Догонялки"
        if mx >= WINDOW_WIDTH/2 + 50 && mx <= WINDOW_WIDTH/2 + 50 + @btn2_img.width*0.5 &&
           my >= WINDOW_HEIGHT/2 - 100 && my <= WINDOW_HEIGHT/2 - 100 + @btn2_img.height*0.5
          close
          GameWindow2.new.show
        end
      end
    when Gosu::KB_ESCAPE
      close
    end
  end
end

MenuWindow.new.show
