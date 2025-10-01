# main.rb
# Требует: gem install gosu
require 'gosu'

WINDOW_WIDTH = 1000
WINDOW_HEIGHT = 600

SHEEP_COUNT = 7             # 1 игрок + 6 ИИ
SHEEP_RADIUS = 36.0         # увеличенный
HORN_OFFSET = 37.0          # передняя точка ("рога")
HORN_RADIUS = 15.0          # радиус зоны рогов для попадания
MAX_SPEED = 400.0
MAX_FORCE = 700.0           # максимальное ускорение
DRAG = 0.95                 # линейный трение
MAX_ANGULAR_SPEED = 8.0     # рад/с (плавность поворота)
TIME_STEP = 1.0 / 60.0

# --- утилиты векторные ---
def clamp(v, a, b) v < a ? a : (v > b ? b : v) end
def len(x, y) Math.hypot(x, y) end
def normalize(x, y)
  l = len(x, y)
  l > 0e-9 ? [x / l, y / l] : [0.0, 0.0]
end
def angle_to_vector(a)
  [Math.cos(a), Math.sin(a)]
end
def vector_to_angle(x, y)
  Math.atan2(y, x)
end
def shortest_angle_diff(target, current)
  a = target - current
  while a <= -Math::PI; a += 2*Math::PI; end
  while a > Math::PI; a -= 2*Math::PI; end
  a
end

# --- Класс Sheep ---
class Sheep
  attr_accessor :x, :y, :vx, :vy, :angle, :alive, :number
  attr_reader :is_player

  def initialize(number, x, y, is_player=false)
    @number = number
    @x = x
    @y = y
    @vx = 0.0
    @vy = 0.0
    @angle = 0.0
    @alive = true
    @is_player = is_player

    # AI state
    @flee_timer = is_player ? 0.0 : 0.6 # Все ИИ начинают в страхе на 0.6 секунды
    @is_coward = !is_player && rand < 0.20 # Примерно 1/5 ботов - трусы

    @target = nil
    @avoid_timer = 0.0
    @wander_time = rand * 3.0
    @desired_direction = nil
  end

  def front_point
    fx = @x + Math.cos(@angle) * HORN_OFFSET
    fy = @y + Math.sin(@angle) * HORN_OFFSET
    [fx, fy]
  end

  def speed
    Math.hypot(@vx, @vy)
  end

  def update(dt, world)
    return unless @alive

    if is_player
      player_control(dt)
    else
      ai_control(dt, world)
    end

    # apply simple physics
    @x += @vx * dt
    @y += @vy * dt

    # drag
    @vx *= DRAG
    @vy *= DRAG

    # clamp speed
    sp = speed
    if sp > MAX_SPEED
      factor = MAX_SPEED / sp
      @vx *= factor
      @vy *= factor
    end

    # Столкновение со стенами
    bounce = -0.4 # Коэффициент отскока
    if @x < SHEEP_RADIUS
      @x = SHEEP_RADIUS
      @vx *= bounce
    elsif @x > WINDOW_WIDTH - SHEEP_RADIUS
      @x = WINDOW_WIDTH - SHEEP_RADIUS
      @vx *= bounce
    end

    if @y < SHEEP_RADIUS
      @y = SHEEP_RADIUS
      @vy *= bounce
    elsif @y > WINDOW_HEIGHT - SHEEP_RADIUS
      @y = WINDOW_HEIGHT - SHEEP_RADIUS
      @vy *= bounce
    end
  end

  # Управление игрока
  def player_control(dt)
    dx = 0.0; dy = 0.0
    if Gosu.button_down?(Gosu::KB_LEFT)
      dx -= 1
    end
    if Gosu.button_down?(Gosu::KB_RIGHT)
      dx += 1
    end
    if Gosu.button_down?(Gosu::KB_UP)
      dy -= 1
    end
    if Gosu.button_down?(Gosu::KB_DOWN)
      dy += 1
    end

    if dx != 0 || dy != 0
      ndx, ndy = normalize(dx, dy)
      desired_angle = vector_to_angle(ndx, ndy)
      rotate_towards(desired_angle, dt)

      fx, fy = angle_to_vector(@angle)
      ax = fx * MAX_FORCE
      ay = fy * MAX_FORCE
      @vx += ax * dt
      @vy += ay * dt
    end
  end

  # Плавный поворот
  def rotate_towards(target_angle, dt)
    diff = shortest_angle_diff(target_angle, @angle)
    max_turn = MAX_ANGULAR_SPEED * dt
    turn = clamp(diff, -max_turn, max_turn)
    @angle += turn
    while @angle <= -Math::PI; @angle += 2*Math::PI; end
    while @angle > Math::PI; @angle -= 2*Math::PI; end
  end

  # Логика ИИ
  def ai_control(dt, world)
    @flee_timer -= dt if @flee_timer > 0

    if @flee_timer <= 0 && @is_coward && rand < (0.1 * dt)
      @flee_timer = 2.0 + rand * 2.5
    end

    if @flee_timer > 0
      flee(dt, world)
    else
      hunt(dt, world)
    end
  end

  # Логика убегания
  def flee(dt, world)
    threats = world.sheeps.select { |s| s.alive && s != self }
    return wander(dt) if threats.empty?

    closest_threat = threats.min_by { |s| len(s.x - @x, s.y - @y) }

    flee_dx = @x - closest_threat.x
    flee_dy = @y - closest_threat.y

    wall_margin = SHEEP_RADIUS * 3.0
    if @x < wall_margin
      flee_dx += 1.5
    elsif @x > WINDOW_WIDTH - wall_margin
      flee_dx -= 1.5
    end
    if @y < wall_margin
      flee_dy += 1.5
    elsif @y > WINDOW_HEIGHT - wall_margin
      flee_dy -= 1.5
    end

    if flee_dx.abs > 1e-6 || flee_dy.abs > 1e-6
      desired_angle = vector_to_angle(flee_dx, flee_dy)
      rotate_towards(desired_angle, dt)
    end

    fx, fy = angle_to_vector(@angle)
    @vx += fx * MAX_FORCE * 1.1 * dt
    @vy += fy * MAX_FORCE * 1.1 * dt
  end

  # Логика охоты
  def hunt(dt, world)
    @avoid_timer -= dt if @avoid_timer > 0

    potential = world.sheeps.select { |s| s.alive && s != self }
    return wander(dt) if potential.empty?

    scored = potential.map do |s|
      d = len(s.x - @x, s.y - @y)
      ang_to_me = vector_to_angle(@x - s.x, @y - s.y)
      facing_diff = (shortest_angle_diff(ang_to_me, s.angle)).abs
      facing_penalty = Math.cos(facing_diff)
      score = d + 400 * (facing_penalty > 0.5 ? 1.0 : 0.0)
      [s, score]
    end
    target, _ = scored.min_by { |pair| pair[1] }
    @target = target

    pvx, pvy = @target.vx, @target.vy
    future_x = @target.x + pvx * 0.25
    future_y = @target.y + pvy * 0.25

    candidates = []
    side_offset = SHEEP_RADIUS * 1.6
    forward_vec = [Math.cos(@target.angle), Math.sin(@target.angle)]
    left_vec = [-forward_vec[1], forward_vec[0]]
    right_vec = [forward_vec[1], -forward_vec[0]]

    candidates << [future_x + left_vec[0] * side_offset, future_y + left_vec[1] * side_offset]
    candidates << [future_x + right_vec[0] * side_offset, future_y + right_vec[1] * side_offset]
    candidates << [future_x - forward_vec[0] * (SHEEP_RADIUS * 1.4), future_y - forward_vec[1] * (SHEEP_RADIUS * 1.4)]

    safe_candidates = candidates.select do |cx, cy|
      !world.danger_at_point?(cx, cy, self)
    end
    target_point = if safe_candidates.empty?
                     @avoid_timer = 0.3
                     candidates.min_by { |cx,cy| len(cx - @x, cy - @y) }
                   else
                     safe_candidates.min_by { |cx,cy| len(cx - @x, cy - @y) }
                   end

    tx, ty = target_point

    steer_x = tx - @x
    steer_y = ty - @y
    steer_norm = normalize(steer_x, steer_y)
    desired_angle = vector_to_angle(steer_norm[0], steer_norm[1])
    rotate_towards(desired_angle, dt)

    avoid = world.predict_horn_conflict(self)
    if avoid
      rotate_towards(vector_to_angle(avoid[0], avoid[1]), dt)
      fx, fy = angle_to_vector(@angle)
      @vx += (fx * MAX_FORCE * 0.8) * dt
      @vy += (fy * MAX_FORCE * 0.8) * dt
      @avoid_timer = 0.25
      return
    end

    d_to_target_center = len(@target.x - @x, @target.y - @y)
    if d_to_target_center < 220
      fx, fy = angle_to_vector(@angle)
      power = 1.6
      if approaching_head_on?(@target)
        side = (rand < 0.5 ? 1 : -1)
        @angle += side * 0.6
        fx, fy = angle_to_vector(@angle)
        @vx += fx * MAX_FORCE * 1.0 * dt
        @vy += fy * MAX_FORCE * 1.0 * dt
      else
        @vx += fx * MAX_FORCE * power * dt
        @vy += fy * MAX_FORCE * power * dt
      end
    else
      fx, fy = angle_to_vector(@angle)
      @vx += fx * MAX_FORCE * 0.45 * dt
      @vy += fy * MAX_FORCE * 0.45 * dt
    end
  end

  def approaching_head_on?(other)
    ang_to_other = vector_to_angle(other.x - @x, other.y - @y)
    my_to_other = shortest_angle_diff(ang_to_other, @angle).abs
    ang_from_other = vector_to_angle(@x - other.x, @y - other.y)
    other_facing_us = shortest_angle_diff(ang_from_other, other.angle).abs
    my_to_other < Math::PI / 6.0 && other_facing_us < Math::PI / 6.0
  end

  def wander(dt)
    @wander_time -= dt
    if @wander_time <= 0
      @wander_time = 1.0 + rand * 3.0
      @desired_direction = rand * 2*Math::PI
    end
    rotate_towards(@desired_direction, dt)
    fx, fy = angle_to_vector(@angle)
    @vx += fx * MAX_FORCE * 0.25 * dt
    @vy += fy * MAX_FORCE * 0.25 * dt
  end

  def die!
    @alive = false
    @vx = @vy = 0.0
  end
end

# --- Мир игры ---
class World
  attr_reader :sheeps

  def initialize
    @sheeps = []
    load_resources
    spawn_sheeps
    @font = Gosu::Font.new(28, bold: true)
    @hud_font = Gosu::Font.new(20)
    @big_font = Gosu::Font.new(48)
    @time = 0.0
    @game_over = false
    @winner = nil
  end

  def load_resources
    @map = Gosu::Image.new("map.png", tileable: false)
    @sheep_img = Gosu::Image.new("sheep.png")
  rescue StandardError => e
    puts "Ошибка загрузки изображений: #{e}"
    exit 1
  end

  def spawn_sheeps
    @sheeps.clear
    cx = WINDOW_WIDTH / 2.0
    cy = WINDOW_HEIGHT / 2.0
    r = [WINDOW_WIDTH, WINDOW_HEIGHT].min * 0.25
    SHEEP_COUNT.times do |i|
      a = (2*Math::PI) * i / SHEEP_COUNT
      x = cx + Math.cos(a) * (r + rand*40 - 20)
      y = cy + Math.sin(a) * (r + rand*40 - 20)
      is_player = (i == 0)
      s = Sheep.new(i+1, x, y, is_player)
      @sheeps << s
    end
  end

  def update(dt)
    return if @game_over
    @time += dt
    @sheeps.each { |s| s.update(dt, self) }
    handle_collisions
    alive = @sheeps.select(&:alive)
    if alive.size <= 1
      @game_over = true
      @winner = alive.first
    end
  end

  def danger_at_point?(px, py, me)
    @sheeps.each do |s|
      next unless s.alive && s != me
      fx, fy = s.front_point
      return true if (px - fx)**2 + (py - fy)**2 <= (HORN_RADIUS*1.2)**2
    end
    false
  end

  def predict_horn_conflict(me)
    dt = 0.22
    my_future_fx = me.x + me.vx * dt + Math.cos(me.angle) * HORN_OFFSET
    my_future_fy = me.y + me.vy * dt + Math.sin(me.angle) * HORN_OFFSET
    @sheeps.each do |s|
      next if s == me || !s.alive
      their_future_fx = s.x + s.vx * dt + Math.cos(s.angle) * HORN_OFFSET
      their_future_fy = s.y + s.vy * dt + Math.sin(s.angle) * HORN_OFFSET
      dist2 = (my_future_fx - their_future_fx)**2 + (my_future_fy - their_future_fy)**2
      if dist2 <= (HORN_RADIUS * 3.0)**2
        dx = s.x - me.x
        dy = s.y - me.y
        nx, ny = normalize(dx, dy)
        avoid = [-ny, nx]
        return avoid
      end
    end
    nil
  end

  def handle_collisions
    alive = @sheeps.select(&:alive)
    # Столкновение тел
    alive.combination(2) do |a, b|
      dx = b.x - a.x
      dy = b.y - a.y
      dist = Math.hypot(dx, dy)
      min_dist = SHEEP_RADIUS * 2.0 - 2.0
      if dist > 0 && dist < min_dist
        overlap = min_dist - dist
        nx = dx / dist; ny = dy / dist
        a.x -= nx * overlap * 0.5
        a.y -= ny * overlap * 0.5
        b.x += nx * overlap * 0.5
        b.y += ny * overlap * 0.5

        rel_vx = b.vx - a.vx
        rel_vy = b.vy - a.vy
        contact_vel = rel_vx * nx + rel_vy * ny
        if contact_vel < 0
          impulse = -contact_vel * 0.9
          a.vx -= nx * impulse * 0.5
          a.vy -= ny * impulse * 0.5
          b.vx += nx * impulse * 0.5
          b.vy += ny * impulse * 0.5
        end
      end
    end

    # ИЗМЕНЕНИЕ: Логика столкновения рогами
    horn_hits = []
    n = alive.length
    (0...n).each do |i|
      a = alive[i]
      (i+1...n).each do |j|
        b = alive[j]
        afx, afy = a.front_point
        bfx, bfy = b.front_point
        # Проверяем, сталкиваются ли рога одной овцы с телом другой
        a_horns_b_body = (afx - b.x)**2 + (afy - b.y)**2 <= SHEEP_RADIUS**2
        b_horns_a_body = (bfx - a.x)**2 + (bfy - a.y)**2 <= SHEEP_RADIUS**2

        # Проверяем, сталкиваются ли рога с рогами
        horns_vs_horns = (afx - bfx)**2 + (afy - bfy)**2 <= (HORN_RADIUS * 2.0)**2

        # Если рога сталкиваются с рогами, это приоритет
        if horns_vs_horns
          # Мощное отталкивание друг от друга, никто не умирает
          dx = b.x - a.x
          dy = b.y - a.y
          nx, ny = normalize(dx, dy)

          # Даем импульс в противоположные стороны
          a.vx -= nx * 250
          a.vy -= ny * 250
          b.vx += nx * 250
          b.vy += ny * 250

        elsif a_horns_b_body
          # Рога А попали в тело Б -> Б может умереть
          horn_hits << [a, b]
        elsif b_horns_a_body
          # Рога Б попали в тело А -> А может умереть
          horn_hits << [b, a]
        end
      end
    end

    # Применение урона от ударов рогами в тело
    horn_hits.each do |attacker, victim|
      next unless attacker.alive && victim.alive

      ang_to_victim = vector_to_angle(victim.x - attacker.x, victim.y - attacker.y)
      forward_diff = shortest_angle_diff(ang_to_victim, attacker.angle).abs

      if forward_diff < Math::PI / 2.5 # Увеличил угол для более надежного срабатывания
        # Убийство
        victim.die!
        # Отдача атакующему
        fx = Math.cos(attacker.angle); fy = Math.sin(attacker.angle)
        attacker.vx += fx * 140 + (rand-0.5)*40
        attacker.vy += fy * 140 + (rand-0.5)*40
      else
        # Если удар не был направленным (например, боком), просто отталкиваем
        attacker.vx = -attacker.vx * 0.4 + (rand-0.5)*60
        attacker.vy = -attacker.vy * 0.4 + (rand-0.5)*60
      end
    end
  end
end

# --- Окно игры (Gosu) ---
class GameWindow1 < Gosu::Window
  def initialize
    super WINDOW_WIDTH, WINDOW_HEIGHT
    self.caption = "Сам за себя"

    @world = World.new
  end

  def update
    return if finished?
    @world.update(TIME_STEP)
  end

  def draw
    map = @world.instance_variable_get(:@map)
    sx = WINDOW_WIDTH.to_f / map.width
    sy = WINDOW_HEIGHT.to_f / map.height
    map.draw(0, 0, 0, sx, sy)

    sheep_img = @world.instance_variable_get(:@sheep_img)
    font = @world.instance_variable_get(:@font)
    hud = @world.instance_variable_get(:@hud_font)
    big = @world.instance_variable_get(:@big_font)

    @world.sheeps.each do |s|
      next unless s.alive
      draw_sheep(s, sheep_img, font)
    end

    draw_hud(hud)

    if finished?
      winner = @world.instance_variable_get(:@winner)
      msg = if winner
              winner.is_player ? "Ты победил! (№1)" : "Победил №#{winner.number}"
            else
              "Игра окончена"
            end
      big.draw_text_rel(msg, WINDOW_WIDTH/2, WINDOW_HEIGHT/2 - 10, 10, 0.5, 0.5, 1.0, 1.0, Gosu::Color::WHITE)
    else
      player = @world.sheeps[0]
      unless player.alive
        hud.draw_text("Ты выбыл. Жди конца игры...", 12, 64, 5, 1.0, 1.0, Gosu::Color::YELLOW)
      end
    end
  end

  def draw_sheep(s, img, font)
    deg = s.angle * 180.0 / Math::PI
    scale = (SHEEP_RADIUS * 2.0) / img.width
    img.draw_rot(s.x, s.y, 5, deg, 0.5, 0.5, scale, scale)

    font_small = Gosu::Font.new(20, bold: true)
    font_small.draw_text_rel(s.number.to_s, s.x + 1, s.y - 10 + 1, 7, 0.5, 0.5, 1.0, 1.0, Gosu::Color::BLACK)
    font_small.draw_text_rel(s.number.to_s, s.x, s.y - 10, 8, 0.5, 0.5, 1.0, 1.0, Gosu::Color::RED)
  end

  def draw_hud(hud)
    Gosu.draw_rect(8, 8, 360, 56, Gosu::Color.rgba(0,0,0,160))
    alive = @world.sheeps.select(&:alive).map(&:number)
    text = alive.map { |n| n == 1 ? "#{n}(ты)" : n.to_s }.join("  ")
    hud.draw_text("Живые бараны: #{text}", 16, 18, 10, 1.0, 1.0, Gosu::Color::WHITE)
    hud.draw_text("R - рестарт, ESC - выход", 16, 36, 10, 0.85, 0.85, Gosu::Color::GRAY)
  end

  def button_down(id)
    case id
    when Gosu::KB_ESCAPE
      close
    when Gosu::KB_R
      @world = World.new
    end
  end

  def finished?
    @world.instance_variable_get(:@game_over)
  end
end

# --- запуск ---
#GameWindow.new.show

