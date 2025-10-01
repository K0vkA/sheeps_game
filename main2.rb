# main1.rb
# Требует: gem install gosu chunky_png
require 'gosu'
require 'chunky_png' # Библиотека для работы с пикселями карты

# --- Глобальные настройки ---
WINDOW_WIDTH = 1000
WINDOW_HEIGHT = 600

SHEEP_RADIUS = 36.0
HORN_OFFSET = 38.0
MAX_SPEED_BASE = 400.0 # Базовая скорость
MAX_FORCE = 700.0
DRAG = 0.95
MAX_ANGULAR_SPEED = 8.0
TIME_STEP = 1.0 / 60.0
GAME_DURATION = 20.0 # Длительность раунда в секундах

# --- Настройки команд ---
TEAM_RED = :red
TEAM_BLUE = :blue
COLOR_RED = Gosu::Color.new(255, 255, 100, 100)
COLOR_BLUE = Gosu::Color.new(255, 100, 150, 255)
COLOR_RED_TEXT = Gosu::Color.new(255, 255, 80, 80)
COLOR_BLUE_TEXT = Gosu::Color.new(255, 120, 180, 255)

# --- Векторные утилиты (без изменений) ---
def clamp(v, a, b) v < a ? a : (v > b ? b : v) end
def len(x, y) Math.hypot(x, y) end
def normalize(x, y)
  l = len(x, y)
  l > 1e-9 ? [x / l, y / l] : [0.0, 0.0]
end
def angle_to_vector(a) [Math.cos(a), Math.sin(a)] end
def vector_to_angle(x, y) Math.atan2(y, x) end
def shortest_angle_diff(target, current)
  (a = target - current) - (2 * Math::PI) * ((a + Math::PI) / (2 * Math::PI)).floor
end

# --- Класс Sheep ---
class Sheep
  attr_accessor :x, :y, :vx, :vy, :angle, :alive, :number, :team
  attr_reader :is_player, :max_speed

  def initialize(number, x, y, team, is_player=false)
    @number = number
    @x = x; @y = y
    @vx = 0.0; @vy = 0.0
    @angle = team == TEAM_RED ? 0.0 : Math::PI # Красные смотрят вправо, синие влево
    @alive = true
    @is_player = is_player
    @team = team

    # Устанавливаем скорость в зависимости от команды
    @max_speed = (team == TEAM_BLUE) ? MAX_SPEED_BASE * 2.0 : MAX_SPEED_BASE

    # AI state
    @wander_time = rand * 3.0
    @desired_direction = @angle
  end

  def front_point; [ @x + Math.cos(@angle) * HORN_OFFSET, @y + Math.sin(@angle) * HORN_OFFSET ]; end
  def speed; Math.hypot(@vx, @vy); end

  def update(dt, world)
    return unless @alive

    if is_player
      player_control(dt, world)
    else
      ai_control(dt, world)
    end

    @x += @vx * dt
    @y += @vy * dt

    @vx *= DRAG
    @vy *= DRAG

    sp = speed
    if sp > @max_speed
      factor = @max_speed / sp
      @vx *= factor
      @vy *= factor
    end
  end

  def player_control(dt, world)
    dx = 0.0; dy = 0.0
    dx -= 1 if Gosu.button_down?(Gosu::KB_LEFT)
    dx += 1 if Gosu.button_down?(Gosu::KB_RIGHT)
    dy -= 1 if Gosu.button_down?(Gosu::KB_UP)
    dy += 1 if Gosu.button_down?(Gosu::KB_DOWN)

    if dx != 0 || dy != 0
      desired_angle = vector_to_angle(dx, dy)
      rotate_towards(desired_angle, dt)
      
      avoid_force = calculate_obstacle_avoidance(world, @angle)
      fx, fy = angle_to_vector(@angle)
      
      ax = fx * MAX_FORCE + avoid_force[0] * MAX_FORCE * 1.5
      ay = fy * MAX_FORCE + avoid_force[1] * MAX_FORCE * 1.5
      
      @vx += ax * dt
      @vy += ay * dt
    end
  end

  def rotate_towards(target_angle, dt)
    diff = shortest_angle_diff(target_angle, @angle)
    max_turn = MAX_ANGULAR_SPEED * dt
    turn = clamp(diff, -max_turn, max_turn)
    @angle += turn
  end

  def ai_control(dt, world)
    case @team
    when TEAM_RED
      hunt(dt, world)
    when TEAM_BLUE
      flee(dt, world)
    end
  end

  # ===================================================================
  # ===== УЛУЧШЕННАЯ ЛОГИКА УБЕГАНИЯ ДЛЯ СИНИХ БАРАНОВ (ИЗМЕНЕНО) =====
  # ===================================================================
  def flee(dt, world)
    threats = world.sheeps.select { |s| s.alive && s.team == TEAM_RED }
    return wander(dt, world) if threats.empty?

    # Находим лучший угол для побега, анализируя окружение
    desired_angle = find_best_escape_route(world, threats)
    rotate_towards(desired_angle, dt)

    # Двигаемся в выбранном безопасном направлении
    fx, fy = angle_to_vector(@angle)
    @vx += fx * MAX_FORCE * 1.1 * dt
    @vy += fy * MAX_FORCE * 1.1 * dt
  end

  def find_best_escape_route(world, threats)
    best_direction_score = -Float::INFINITY
    best_direction_angle = @angle
    
    # Проверяем 16 направлений вокруг
    16.times do |i|
      angle = i * (2 * Math::PI / 16.0)
      direction_score = 0.0

      # 1. Оценка угрозы от врагов
      # Чем дальше направление от всех врагов, тем лучше
      threats.each do |threat|
        angle_to_threat = vector_to_angle(threat.x - @x, threat.y - @y)
        # shortest_angle_diff вернет значение от -PI до PI. 
        # Чем ближе к PI (или -PI), тем направление безопаснее.
        # Берем абсолютное значение, чтобы получить "удаленность" от направления на врага
        score = shortest_angle_diff(angle, angle_to_threat).abs / Math::PI # Нормализуем от 0 до 1
        direction_score += score / (len(threat.x - @x, threat.y - @y) / 100.0 + 1.0) # Ближние враги важнее
      end
      
      # 2. Оценка препятствий
      # Проверяем, свободно ли направление
      check_dist = SHEEP_RADIUS * 4.0
      check_x = @x + Math.cos(angle) * check_dist
      check_y = @y + Math.sin(angle) * check_dist
      
      if world.is_obstacle?(check_x, check_y)
        direction_score -= 1000.0 # Огромный штраф, если путь ведет в стену
      end

      # Выбираем направление с наилучшей (самой высокой) оценкой
      if direction_score > best_direction_score
        best_direction_score = direction_score
        best_direction_angle = angle
      end
    end
    
    return best_direction_angle
  end


  # Логика охоты (для красных)
  def hunt(dt, world)
    targets = world.sheeps.select { |s| s.alive && s.team == TEAM_BLUE }
    return wander(dt, world) if targets.empty?

    target = targets.min_by { |t| len(t.x - @x, t.y - @y) }
    
    future_x = target.x + target.vx * 0.2
    future_y = target.y + target.vy * 0.2
    
    steer_x = future_x - @x
    steer_y = future_y - @y
    
    desired_angle = vector_to_angle(steer_x, steer_y)
    
    # Уклонение от стен для охотника
    avoid_force = calculate_obstacle_avoidance(world, desired_angle)
    if len(avoid_force[0], avoid_force[1]) > 0.1
      final_vec_x = steer_x + avoid_force[0] * 500
      final_vec_y = steer_y + avoid_force[1] * 500
      desired_angle = vector_to_angle(final_vec_x, final_vec_y)
    end
    
    rotate_towards(desired_angle, dt)

    fx, fy = angle_to_vector(@angle)
    @vx += fx * MAX_FORCE * 1.2 * dt
    @vy += fy * MAX_FORCE * 1.2 * dt
  end
  
  # Общая логика уклонения от препятствий (для охотников и игрока)
  def calculate_obstacle_avoidance(world, current_direction_angle)
    avoid_force = [0.0, 0.0]
    whiskers = [ current_direction_angle, current_direction_angle - 0.4, current_direction_angle + 0.4 ]
    check_distance = SHEEP_RADIUS * 1.3

    whiskers.each do |a|
      check_x = @x + Math.cos(a) * check_distance
      check_y = @y + Math.sin(a) * check_distance
      
      if world.is_obstacle?(check_x, check_y)
        # Сила, перпендикулярная направлению на стену
        avoid_force[0] -= Math.cos(a)
        avoid_force[1] -= Math.sin(a)
      end
    end
    normalize(avoid_force[0], avoid_force[1])
  end

  def wander(dt, world)
    @wander_time -= dt
    if @wander_time <= 0 || world.is_obstacle?(@x + Math.cos(@desired_direction)*SHEEP_RADIUS*2, @y + Math.sin(@desired_direction)*SHEEP_RADIUS*2)
      @wander_time = 1.5 + rand * 2.0
      @desired_direction = rand * 2 * Math::PI
    end
    
    rotate_towards(@desired_direction, dt)
    fx, fy = angle_to_vector(@angle)
    @vx += fx * MAX_FORCE * 0.25 * dt
    @vy += fy * MAX_FORCE * 0.25 * dt
  end

  def die!; @alive = false; end
end

# --- Мир игры (без изменений) ---
class World
  attr_reader :sheeps, :timer

  def initialize
    load_resources
    @collision_map = create_collision_map(@map_image)
    
    @sheeps = []
    spawn_sheeps
    
    @font = Gosu::Font.new(20, bold: true)
    @hud_font = Gosu::Font.new(24)
    @big_font = Gosu::Font.new(60, bold: true)
    
    @timer = GAME_DURATION
    @game_over = false
    @winner_team = nil
  end

  def load_resources
    @map = Gosu::Image.new("map2.png", tileable: false)
    @sheep_img = Gosu::Image.new("sheep.png")
    @map_image = ChunkyPNG::Image.from_file("map2.png")
  rescue StandardError => e
    puts "Ошибка загрузки ресурсов: #{e}. Убедись, что файлы map2.png и sheep.png существуют."
    exit 1
  end

  def create_collision_map(image)
    map = Array.new(image.height) { Array.new(image.width, false) }
    image.height.times do |y|
      image.width.times do |x|
        pixel_color = image[x, y]
        r = ChunkyPNG::Color.r(pixel_color)
        g = ChunkyPNG::Color.g(pixel_color)
        b = ChunkyPNG::Color.b(pixel_color)
        map[y][x] = true if r < 10 && g < 10 && b < 10
      end
    end
    map
  end

  def is_obstacle?(x, y)
    return true if x < 0 || x >= WINDOW_WIDTH || y < 0 || y >= WINDOW_HEIGHT
    @collision_map.dig(y.to_i, x.to_i)
  end

  def spawn_sheeps
    @sheeps.clear
    @sheeps << Sheep.new(1, 100, WINDOW_HEIGHT / 2.0 - 50, TEAM_RED, true)
#    @sheeps << Sheep.new(2, 100, WINDOW_HEIGHT / 2.0 + 50, TEAM_RED, false)
    @sheeps << Sheep.new(3, WINDOW_WIDTH - 100, WINDOW_HEIGHT / 2.0 - 80, TEAM_BLUE)
    @sheeps << Sheep.new(4, WINDOW_WIDTH - 100, WINDOW_HEIGHT / 2.0,      TEAM_BLUE)
    @sheeps << Sheep.new(5, WINDOW_WIDTH - 100, WINDOW_HEIGHT / 2.0 + 80, TEAM_BLUE)
  end

  def update(dt)
    return if @game_over
    
    @timer -= dt
    @sheeps.each { |s| s.update(dt, self) }
    handle_collisions
    
    blue_alive_count = @sheeps.count { |s| s.team == TEAM_BLUE && s.alive }
    
    if blue_alive_count == 0
      @game_over = true
      @winner_team = TEAM_RED
    elsif @timer <= 0
      @game_over = true
      @winner_team = TEAM_BLUE
    end
  end

  def handle_collisions
    alive = @sheeps.select(&:alive)
    
    alive.each do |s|
      8.times do |i|
        angle = i * (Math::PI / 4)
        check_x = s.x + Math.cos(angle) * SHEEP_RADIUS
        check_y = s.y + Math.sin(angle) * SHEEP_RADIUS
        
        if is_obstacle?(check_x, check_y)
          push_x = s.x - check_x; push_y = s.y - check_y
          nx, ny = normalize(push_x, push_y)
          s.x += nx * 1.5; s.y += ny * 1.5
          s.vx *= 0.8; s.vy *= 0.8
          break
        end
      end
    end
    
    alive.combination(2) do |a, b|
      dx = b.x - a.x; dy = b.y - a.y
      dist = Math.hypot(dx, dy)
      min_dist = SHEEP_RADIUS * 2.0
      if dist > 0 && dist < min_dist
        overlap = min_dist - dist
        nx = dx / dist; ny = dy / dist
        a.x -= nx * overlap * 0.5; a.y -= ny * overlap * 0.5
        b.x += nx * overlap * 0.5; b.y += ny * overlap * 0.5
      end
    end

    red_team = alive.select { |s| s.team == TEAM_RED }
    blue_team = alive.select { |s| s.team == TEAM_BLUE }

    red_team.each do |attacker|
      afx, afy = attacker.front_point
      blue_team.each do |victim|
        if (afx - victim.x)**2 + (afy - victim.y)**2 <= SHEEP_RADIUS**2
          ang_to_victim = vector_to_angle(victim.x - attacker.x, victim.y - attacker.y)
          forward_diff = shortest_angle_diff(ang_to_victim, attacker.angle).abs
          
          if forward_diff < Math::PI / 2.5
            victim.die!
            attacker.vx += Math.cos(attacker.angle) * 100
            attacker.vy += Math.sin(attacker.angle) * 100
          end
        end
      end
    end
  end
  
  def game_over?; @game_over; end
  def winner; @winner_team; end
end

# --- Окно игры (без изменений) ---
class GameWindow2 < Gosu::Window
  def initialize
    super WINDOW_WIDTH, WINDOW_HEIGHT
    self.caption = "Догонялки"
    @world = World.new
  end

  def update
    @world.update(TIME_STEP) unless @world.game_over?
  end

  def draw
    map = @world.instance_variable_get(:@map)
    sheep_img = @world.instance_variable_get(:@sheep_img)
    font = @world.instance_variable_get(:@font)
    hud_font = @world.instance_variable_get(:@hud_font)
    big_font = @world.instance_variable_get(:@big_font)
    
    map.draw(0, 0, 0)

    @world.sheeps.each do |s|
      next unless s.alive
      draw_sheep(s, sheep_img, font)
    end

    draw_hud(hud_font)

    if @world.game_over?
      winner = @world.winner
      msg = (winner == TEAM_RED) ? "Красные выиграли!" : "Синие выиграли!"
      color = (winner == TEAM_RED) ? COLOR_RED_TEXT : COLOR_BLUE_TEXT
      
      Gosu.draw_rect(0, WINDOW_HEIGHT/2 - 50, WINDOW_WIDTH, 100, Gosu::Color.rgba(0,0,0,180), 10)
      big_font.draw_text_rel(msg, WINDOW_WIDTH/2, WINDOW_HEIGHT/2, 11, 0.5, 0.5, 1.0, 1.0, color)
    end
  end

  def draw_sheep(s, img, font)
    deg = s.angle * 180.0 / Math::PI
    scale = (SHEEP_RADIUS * 2.0) / img.width
    color = (s.team == TEAM_RED) ? COLOR_RED : COLOR_BLUE
    
    img.draw_rot(s.x, s.y, 5, deg, 0.5, 0.5, scale, scale, color)

    text_color = (s.team == TEAM_RED) ? COLOR_RED_TEXT : COLOR_BLUE_TEXT
    font.draw_text_rel(s.number.to_s, s.x, s.y - SHEEP_RADIUS * 0.7, 8, 0.5, 0.5, 1.0, 1.0, text_color)
  end

  def draw_hud(hud)
    Gosu.draw_rect(8, 8, 300, 56, Gosu::Color.rgba(0,0,0,160), 10)
    
    timer_text = "Время: %.1f" % @world.timer
    hud.draw_text(timer_text, WINDOW_WIDTH - 150, 18, 10, 1.0, 1.0, Gosu::Color::WHITE)
    
    prefix = "Живые бараны: "
    hud.draw_text(prefix, 16, 18, 10, 1.0, 1.0, Gosu::Color::WHITE)
    
    current_x = 16 + hud.text_width(prefix)
    alive_sheeps = @world.sheeps.select(&:alive).sort_by(&:number)
    
    alive_sheeps.each do |s|
      num_str = s.number.to_s
      num_str = "(ты)#{num_str}" if s.is_player
      
      color = (s.team == TEAM_RED) ? COLOR_RED_TEXT : COLOR_BLUE_TEXT
      hud.draw_text(num_str, current_x, 18, 10, 1.0, 1.0, color)
      current_x += hud.text_width(num_str) + 10
    end
    
    hud.draw_text("R - рестарт, ESC - выход", 16, 38, 10, 0.85, 0.85, Gosu::Color::GRAY)
  end

  def button_down(id)
    case id
    when Gosu::KB_ESCAPE; close
    when Gosu::KB_R; @world = World.new
    end
  end
end

# --- Запуск игры ---
#GameWindow.new.show

