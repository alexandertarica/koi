import SwiftUI
import SwiftData
import KoiShared

struct TodoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendarProvider) private var calendarProvider
    @Environment(\.notificationProvider) private var notificationProvider
    @Environment(\.analyticsProvider) private var analyticsProvider
    @State private var model = TodoViewModel()
    @AppStorage("koiTodoGrid") private var startsInMatrix = false
    @State private var showFinished = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KoiTheme.space.s13) {
                header.modifier(KoiIntroReveal(order: 0))
                if model.showingArchive { archiveContent.modifier(KoiIntroReveal(order: 2)) }
                else if model.showingNewTask { NewTaskSheet(model: model, embedded: true).modifier(KoiIntroReveal(order: 1)) }
                else if model.showingNewHabit { NewHabitSheet(model: model, embedded: true).modifier(KoiIntroReveal(order: 1)) }
                else {
                    if model.shouldShowCoach { habitCoachCard.modifier(KoiIntroReveal(order: 2)) }
                    if !todayHabits.isEmpty { habitsSection.modifier(KoiIntroReveal(order: 2)) }
                    if model.mode == .list { listContent.modifier(KoiIntroReveal(order: 3)) } else { matrixContent.modifier(KoiIntroReveal(order: 3)) }
                }
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, KoiTheme.space.s13)
            .padding(.bottom, KoiTheme.space.s34)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            model.setMode(startsInMatrix ? .matrix : .list)
            model.load(modelContext, calendarProvider: calendarProvider, notificationProvider: notificationProvider)
            switch KoiLaunch.screen {
            case "todoNew", "newTodo": model.beginTask()
            case "newHabit": model.beginHabit()
            default: break
            }
        }
        .alert("Keep this for later?", isPresented: Binding(get: { model.staleTaskID != nil }, set: { if !$0 { model.dismissStaleTask(keep: true) } })) {
            Button("Keep", role: .cancel) { model.dismissStaleTask(keep: true) }
            Button("Let go", role: .destructive) { model.dismissStaleTask(keep: false) }
        } message: { Text("This someday to-do has been quiet for a week.") }
        .alert("Couldn't save", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "Try again.") }
        .overlay(alignment: .top) {
            if model.autoUrgentMessage != nil {
                HStack(spacing: 8) {
                    Text(model.autoUrgentMessage ?? "")
                    Spacer(minLength: 8)
                    Button("Undo") { if let id = model.toastTaskID, let task = model.tasks.first(where: { $0.id == id }) { model.undoAutoUrgent(task) } }
                        .underline()
                    Button { model.dismissAutoUrgent() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss")
                }
                .font(KoiTheme.caption)
                .padding(13)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(KoiTheme.onBase.opacity(0.3)))
                .padding(.horizontal, 21).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image("KoiWordmark").resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 240, height: 28).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95))
                    .accessibilityLabel("Koi")
                Spacer()
                Button {
                    KoiHaptics.tap()
                    withAnimation(KoiTheme.morph) {
                        if model.showingNewTask { model.cancelNewTask() }
                        else if model.showingNewHabit { model.cancelNewHabit() }
                        else { model.toggleArchive() }
                    }
                } label: {
                    Image(systemName: model.showingArchive || model.showingNewTask || model.showingNewHabit ? "xmark" : "archivebox")
                        .font(.system(size: 21, weight: .light)).foregroundStyle(KoiTheme.onBase)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .padding(.vertical, -8)
                .buttonStyle(.plain)
                .accessibilityLabel(model.showingArchive || model.showingNewTask || model.showingNewHabit ? "Close" : "Archive")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(KoiTheme.section).tracking(2.7).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95).opacity(0.88)).padding(.top, 7)
                Text(model.showingArchive ? "Archive" : (model.showingNewTask ? (model.editingTaskID == nil ? "New to-do" : "Edit to-do") : model.showingNewHabit ? (model.editingHabitID == nil ? "New habit" : "Edit habit") : "Practice"))
                    .font(KoiTheme.title).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.95)).padding(.top, 3)
            }
            if model.showingArchive || model.showingNewTask || model.showingNewHabit {
                EmptyView()
            } else {
                HStack(spacing: KoiTheme.space.s8) {
                    Button { KoiHaptics.tap(); model.beginTask() } label: { GlassChip(title: "To-do", symbol: "plus") }
                        .buttonStyle(.plain)
                    Button { KoiHaptics.tap(); model.beginHabit() } label: { GlassChip(title: "Habit", symbol: "plus") }
                        .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    if todayTotal > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(todayDone)").contentTransition(.numericText())
                            Text("of \(todayTotal) done").font(KoiTheme.caption)
                        }
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, KoiTheme.space.s21)
            }
        }
    }

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 11) {
                    ForEach(todayHabits) { habit in habitRing(habit) }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var todayHabits: [KoiHabit] {
        let calendar = Calendar.autoupdatingCurrent
        let weekday = calendar.component(.weekday, from: .now)
        let day = calendar.component(.day, from: .now)
        return model.activeHabits.filter { habit in
            guard habit.graduatedAt == nil else { return false }
            switch habit.schedule {
            case "weekly": return calendar.component(.weekday, from: habit.createdAt) == weekday
            case "monthly": return calendar.component(.day, from: habit.createdAt) == day
            case "someDays": return habit.weekdays.contains(weekday)
            default: return true
            }
        }
    }

    private var dueTodayTasks: [KoiTask] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        return model.pendingTasks.filter { task in
            guard let due = task.dueAt else { return false }
            return calendar.startOfDay(for: due) <= today
        }.sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
    }

    private var allDueTodayTasks: [KoiTask] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        return model.activeTasks.filter { task in
            guard let due = task.dueAt else { return false }
            return calendar.startOfDay(for: due) == today
        }
    }

    private var undatedTasks: [KoiTask] {
        model.pendingTasks.filter { $0.dueAt == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    private var upcomingTasks: [KoiTask] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        return model.pendingTasks.filter { task in
            guard let due = task.dueAt else { return false }
            return calendar.startOfDay(for: due) > today
        }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var todayTotal: Int { todayHabits.count + allDueTodayTasks.count }
    private var todayDone: Int {
        todayHabits.filter { model.todayCompletion(for: $0) > 0 }.count
            + allDueTodayTasks.filter(\.isComplete).count
    }

    private func habitRing(_ habit: KoiHabit) -> some View {
        let complete = model.todayCompletion(for: habit) > 0
        return VStack(spacing: 6) {
            Button {
                if !complete { analyticsProvider.signal("Habit.completed") }
                KoiHaptics.check()
                withAnimation(.snappy) { model.toggleHabit(habit) }
            } label: {
                ZStack {
                    ForEach(0..<24, id: \.self) { index in
                        let completion = model.todayCompletion(for: habit)
                        let progress = completion >= 2 ? 24 : completion == 1 ? 12 : 0
                        Capsule().fill(KoiTheme.onBase.opacity(index < progress ? 0.92 : 0.28))
                            .frame(width: 1, height: index.isMultiple(of: 4) ? 6 : 3)
                            .offset(y: -21)
                            .rotationEffect(.degrees(Double(index) * 15))
                    }
                    Text(String(habit.title.prefix(1)).uppercased())
                        .font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.8))
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Check in: \(habit.title)")
            .accessibilityValue(complete ? "Done" : "Not done")
            .disabled(habit.graduatedAt != nil)
            .overlay(alignment: .topTrailing) {
                let streak = habitStreak(for: habit)
                if streak > 0 {
                    HStack(spacing: 1) {
                        Image("KoiFlame").resizable().renderingMode(.template).scaledToFit().frame(height: 9)
                        Text("\(streak)").font(.system(size: 12, weight: .medium)).contentTransition(.numericText())
                    }
                    .foregroundStyle(KoiTheme.onBase)
                    .offset(x: 8, y: -4)
                }
            }
            Text(habit.title)
                .font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(width: 62).opacity(complete ? 0.6 : 1)
        }
        .frame(width: 62)
        .contentShape(Rectangle())
        .onLongPressGesture { KoiHaptics.tap(); model.beginEditingHabit(habit) }
    }

    private func habitStreak(for habit: KoiHabit) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let completedDates = model.logs.filter { $0.habitID == habit.id && $0.completion > 0 }
            .map { calendar.startOfDay(for: $0.date) }
        var cursor = calendar.startOfDay(for: .now)
        if !completedDates.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        var count = 0
        while cursor >= calendar.startOfDay(for: habit.createdAt) {
            if !habitIsScheduled(habit, on: cursor, calendar: calendar) {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
                continue
            }
            guard completedDates.contains(cursor) else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private func habitIsScheduled(_ habit: KoiHabit, on date: Date, calendar: Calendar) -> Bool {
        switch habit.schedule {
        case "weekly": calendar.component(.weekday, from: date) == calendar.component(.weekday, from: habit.createdAt)
        case "monthly": calendar.component(.day, from: date) == calendar.component(.day, from: habit.createdAt)
        case "someDays": habit.weekdays.contains(calendar.component(.weekday, from: date))
        default: true
        }
    }

    private var habitCoachCard: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            Text("SUNDAY RECAP").font(KoiTheme.section).tracking(1.8)
            Text(coachMessage).font(KoiTheme.body)
            if let habit = model.coachHabit { Text(habit.title).font(KoiTheme.caption).opacity(0.72) }
            HStack(spacing: KoiTheme.space.s13) {
                Button(coachButtonTitle) { KoiHaptics.success(); model.reviewHabitCoach() }.font(KoiTheme.caption).buttonStyle(.plain)
                Spacer()
                Button("Not now") { KoiHaptics.tap(); model.dismissHabitCoach() }.font(KoiTheme.caption).buttonStyle(.plain).opacity(0.7)
            }
        }
        .padding(KoiTheme.space.s13)
        .background(.ultraThinMaterial.opacity(0.24), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KoiTheme.onBase.opacity(0.2), lineWidth: 1))
    }

    private var coachMessage: String {
        switch model.coachAction {
        case .easeOff: "A gentler weekly rhythm may fit better."
        case .stepUp(_): "You’ve been steady for four weeks. Keep this amount as your minimum."
        case .graduate: "This habit has been steady for 66 days. It may be ready to graduate."
        case .stack(let strongest): "Try a new habit after \(strongest)."
        case nil: ""
        }
    }

    private var coachButtonTitle: String { model.coachAction == .graduate ? "Graduate" : (model.coachAction == nil ? "Review" : "Review habit") }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            if model.pendingTasks.isEmpty {
                if todayHabits.isEmpty {
                    Text("Clear water. No tasks for today.")
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase.opacity(0.75))
                        .padding(.top, KoiTheme.space.s13)
                }
            } else {
                taskViewToggle(title: dueTodayTasks.isEmpty ? "To-dos" : "Today's to-dos")
                if !dueTodayTasks.isEmpty {
                    taskSection(nil, tasks: dueTodayTasks, compact: false)
                }
                if !undatedTasks.isEmpty {
                    taskSection("Undated", tasks: undatedTasks, compact: false)
                }
                if !upcomingTasks.isEmpty {
                    taskSection("Upcoming", tasks: upcomingTasks, compact: false)
                }
            }
        }
    }

    private func taskViewToggle(title: String) -> some View {
        HStack(spacing: KoiTheme.space.s8) {
            sectionLabel(title)
            Spacer()
            ForEach(TodoMode.allCases) { mode in
                Button {
                    KoiHaptics.tap()
                    startsInMatrix = mode == .matrix
                    withAnimation(KoiTheme.morph) { model.setMode(mode) }
                } label: {
                    Image(systemName: mode == .matrix ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(KoiTheme.onBase)
                        .frame(width: 36, height: 32)
                        .background(Capsule().fill(.white.opacity(model.mode == mode ? 0.22 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode == .matrix ? "Grid view" : "List view")
                .accessibilityIdentifier(mode == .matrix ? "stage.todo.matrix" : "stage.todo.list")
                .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
            }
        }
    }

    private func taskSection(_ title: String?, tasks: [KoiTask], compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s8) {
            if let title { sectionLabel(title) }
            VStack(spacing: 0) { ForEach(tasks) { taskRow($0, compact: compact) } }
        }
    }

    private var matrixContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            taskViewToggle(title: "To-dos")
            HStack(spacing: 0) {
                Text("URGENT").font(KoiTheme.section).tracking(1.5).frame(maxWidth: .infinity, alignment: .leading)
                Text("NOT URGENT").font(KoiTheme.section).tracking(1.5).frame(maxWidth: .infinity, alignment: .trailing)
            }.foregroundStyle(KoiTheme.onBase.opacity(0.8))
            HStack(alignment: .top, spacing: 8) {
                matrixColumn([.urgentImportant, .urgentNotImportant])
                matrixColumn([.notUrgentImportant, .someday])
            }
            if model.pendingTasks.isEmpty { Text("Clear").font(KoiTheme.body).foregroundStyle(KoiTheme.onBase.opacity(0.65)) }
        }
    }

    private func matrixColumn(_ sections: [TodoSection]) -> some View {
        VStack(spacing: 8) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(section.title.uppercased()).font(KoiTheme.section).tracking(1); Spacer(); Text("\(model.count(in: section))").font(KoiTheme.caption) }
                        .foregroundStyle(KoiTheme.onBase.opacity(0.82))
                    if model.tasks(in: section).isEmpty {
                        Text("A little space").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.58)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    } else {
                        ForEach(model.tasks(in: section)) { task in
                            taskRow(task, compact: true)
                                .draggable(task.id.uuidString)
                        }
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                .background(.ultraThinMaterial.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(KoiTheme.onBase.opacity(0.22)))
                .dropDestination(for: String.self) { values, _ in
                    guard let id = values.first.flatMap(UUID.init(uuidString:)), let task = model.tasks.first(where: { $0.id == id }) else { return false }
                            KoiHaptics.land(); model.move(task, to: section); return true
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(section == .notUrgentImportant ? "stage.todo.important" : "todo.quadrant.\(section.quadrant)")
            }
        }
    }

    private func taskRow(_ task: KoiTask, compact: Bool) -> some View {
        let toggle: () -> Void = {
            if !task.isComplete { analyticsProvider.signal("Task.completed") }
            if task.isComplete { KoiHaptics.tap() } else { KoiHaptics.check() }
            model.toggleCompletion(task)
        }
        let delete: () -> Void = { KoiHaptics.tap(); model.deleteTask(task) }
        return VStack(spacing: 0) {
            TodoSwipeRow(isDone: task.isComplete, onComplete: toggle, onDelete: delete) {
                HStack(spacing: 13) {
                    Button(action: toggle) { CheckCircle(isOn: task.isComplete) }
                        .buttonStyle(.plain).accessibilityLabel(task.isComplete ? "Reopen \(task.title)" : "Complete \(task.title)")
                    Button {
                        KoiHaptics.tap()
                        withAnimation(KoiTheme.morph) { model.openTask(task) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).font(.custom("RobotoMono-Light", size: 15)).strikethrough(task.isComplete).foregroundStyle(KoiTheme.onBase).lineLimit(2)
                                .accessibilityLabel(task.title == "3-mile run" && task.quadrant == TodoSection.notUrgentImportant.quadrant ? "3-mile run, Important" : task.title)
                            if !compact, let dueAt = task.dueAt,
                               Calendar.current.startOfDay(for: dueAt) <= Calendar.current.startOfDay(for: .now),
                               !model.tasksMarkedUrgent.contains(task.id),
                               let due = model.dueLabel(for: task) {
                                HStack(spacing: 4) {
                                    Text(due)
                                    if task.hasTime && task.calendarEventID != nil { Image(systemName: "calendar").accessibilityLabel("On your calendar") }
                                }
                                .font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.68))
                            }
                            if !compact, !task.isComplete, let dueAt = task.dueAt, Calendar.current.startOfDay(for: dueAt) < Calendar.current.startOfDay(for: .now) {
                                Text("Overdue · \(dueAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.68))
                            }
                            if !compact, model.tasksMarkedUrgent.contains(task.id) {
                                HStack(spacing: KoiTheme.space.s8) {
                                    Text("Due soon · marked urgent")
                                    Button("Undo") { KoiHaptics.tap(); model.undoAutoUrgent(task) }.underline()
                                }
                                .font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.7))
                                .buttonStyle(.plain)
                            }
                            if !compact, model.currentSection(for: task) == .someday {
                                let days = max(0, Calendar.current.dateComponents([.day], from: task.lastTouchedAt, to: .now).day ?? 0)
                                if days > 0 { Text("Waiting \(days) days").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.68)) }
                            }
                            if !compact, let note = task.notes.nilIfBlank {
                                Text(note).font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.68)).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier(task.title == "3-mile run" ? "stage.todo.run" : "")
                        .accessibilityLabel(task.title == "3-mile run" && task.quadrant == TodoSection.notUrgentImportant.quadrant ? "3-mile run, Important" : task.title)
                    if !compact, let dueAt = task.dueAt,
                       Calendar.current.startOfDay(for: dueAt) > Calendar.current.startOfDay(for: .now) {
                        Text(model.dueLabel(for: task) ?? "")
                            .font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.72))
                            .frame(minWidth: 46, alignment: .trailing)
                    }
                }
                .frame(minHeight: 44)
            }
            if model.selectedTaskID == task.id { taskDetail(task) }
            Rectangle().fill(KoiTheme.divider.opacity(0.6)).frame(height: 0.5)
        }
        .contextMenu {
            ForEach(TodoSection.allCases) { section in Button("Move to \(section.title)") { model.move(task, to: section) } }
            Button("Delete", role: .destructive) { model.deleteTask(task) }
        }
    }

    private func taskDetail(_ task: KoiTask) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) { ForEach(TodoSection.allCases) { section in Button { KoiHaptics.change(); withAnimation(KoiTheme.morph) { model.move(task, to: section) } } label: { GlassChip(title: section.title, isOn: model.currentSection(for: task) == section) }.buttonStyle(.plain) } }
            Button(task.dueAt == nil ? "Add a due date" : "Remove due date") {
                KoiHaptics.tap()
                if task.dueAt == nil { model.setDueDate(task, date: .now) } else { model.setDueDate(task, date: nil) }
            }.buttonStyle(QuietTextButtonStyle())
            if task.dueAt != nil {
                DatePicker("Due", selection: Binding(get: { task.dueAt ?? .now }, set: { model.setDueDate(task, date: $0) }), displayedComponents: [.date, .hourAndMinute])
                    .font(KoiTheme.caption).tint(KoiTheme.onBase).foregroundStyle(KoiTheme.onBase)
            }
            if let note = task.notes.nilIfBlank { Text(note).font(KoiTheme.body).foregroundStyle(KoiTheme.onBase.opacity(0.8)) }
            if task.urgentOverride == false && model.isUrgent(task) == false { Text("Marked not urgent").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.7)) }
            HStack {
                Button("Edit") { KoiHaptics.tap(); model.beginEditingTask(task) }.buttonStyle(QuietTextButtonStyle())
                Spacer()
                Button("Archive") { KoiHaptics.tap(); model.archiveTask(task) }.buttonStyle(QuietTextButtonStyle())
            }
        }.padding(.vertical, 13)
    }

    private func habitDetail(_ habit: KoiHabit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !habit.note.isEmpty { Text(habit.note).font(KoiTheme.body).foregroundStyle(KoiTheme.onBase.opacity(0.78)) }
            Text("Schedule · \(scheduleLabel(habit))").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.75))
            if let time = habit.reminderTime { Text("Reminder · \(time.formatted(date: .omitted, time: .shortened))").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.75)) }
            if !habit.minimumVersion.isEmpty { Button("Minimum · \(habit.minimumVersion)") { model.toggleHabit(habit, minimum: true) }.buttonStyle(QuietTextButtonStyle()) }
            if !habit.stackingCue.isEmpty { Text("After \(habit.stackingCue)").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.75)) }
            HStack {
                Button("Edit") { KoiHaptics.tap(); model.beginEditingHabit(habit) }.buttonStyle(QuietTextButtonStyle())
                Spacer()
                Button("Pause habit") { KoiHaptics.tap(); model.pauseHabit(habit) }.buttonStyle(QuietTextButtonStyle())
            }
        }.padding(.vertical, 8)
    }

    private var archiveContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            if model.archivedTasks.isEmpty && model.pausedHabits.isEmpty {
                Text("Nothing archived yet.\nCompleted to-dos settle here after a day.")
                    .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase.opacity(0.75))
                    .padding(.top, KoiTheme.space.s21)
            }
            if !model.pausedHabits.isEmpty {
                sectionLabel("ARCHIVED HABITS")
                ForEach(model.pausedHabits) { habit in
                    archiveRow(habit.title, subtitle: scheduleLabel(habit), symbol: "repeat", restore: { model.restoreHabit(habit) }, delete: { model.deleteHabit(habit) })
                }
            }
            if !model.archivedTasks.isEmpty {
                sectionLabel("COMPLETED TO-DOS")
                ForEach(model.archivedTasks) { task in
                    archiveRow(task.title, subtitle: task.completedAt.map { "Completed \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Completed", symbol: "checkmark", restore: { model.restoreTask(task) }, delete: { model.deleteTask(task) })
                }
            }
        }
    }

    private func archiveRow(_ title: String, subtitle: String, symbol: String, restore: @escaping () -> Void, delete: @escaping () -> Void) -> some View {
        HStack(spacing: KoiTheme.space.s8) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(KoiTheme.onBase.opacity(0.65)).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KoiTheme.body).foregroundStyle(KoiTheme.onBase)
                Text(subtitle).font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.65))
            }
            Spacer()
            Button(action: restore) { Image(systemName: "arrow.uturn.backward").font(.system(size: 14)).frame(width: 36, height: 36) }
                .buttonStyle(.plain).accessibilityLabel("Restore \(title)")
            Button(action: delete) { Image(systemName: "trash").font(.system(size: 14)).frame(width: 36, height: 36) }
                .buttonStyle(.plain).accessibilityLabel("Delete \(title)")
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.divider).frame(height: 0.5) }
    }

    private func sectionLabel(_ text: String) -> some View { Text(text.uppercased()).font(KoiTheme.section).tracking(2.4).foregroundStyle(KoiTheme.onBase.opacity(0.78)) }
    private func scheduleLabel(_ habit: KoiHabit) -> String {
        if habit.schedule == "weekly" { return "Weekly" }
        if habit.schedule == "monthly" { return "Monthly" }
        if habit.schedule == "someDays" {
            let names = habit.weekdays.compactMap { weekdayName($0) }
            return names.isEmpty ? "Some days" : names.joined(separator: " · ")
        }
        return "Daily"
    }
    private func weekdayName(_ value: Int) -> String? {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard (1...symbols.count).contains(value) else { return nil }
        return symbols[value - 1]
    }
}

private struct NewTaskSheet: View {
    @Bindable var model: TodoViewModel
    @Environment(\.analyticsProvider) private var analyticsProvider
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    private let prompts = ["What needs doing?", "On your mind?", "One thing…", "What's next?"]

    var body: some View {
        Group {
            if embedded {
                formContent
            } else {
                NavigationStack {
                    ScrollView { formContent }
                        .background(KoiBackground().ignoresSafeArea())
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Cancel") { model.cancelNewTask(); dismiss() }
                                    .foregroundStyle(KoiTheme.onBase)
                            }
                        }
                }
            }
        }
        .presentationDetents(embedded ? [] : [.large])
        .preferredColorScheme(embedded ? nil : .dark)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { titleFocused = true } }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 21) {
                    TextField("", text: Binding(get: { model.taskDraft.title }, set: { value in model.updateTaskTitle(value) }), prompt: Text(prompts[Int(Date.now.timeIntervalSince1970 / 86400) % prompts.count]).foregroundColor(KoiTheme.onBase.opacity(0.68)), axis: .vertical)
                        .font(.custom("RobotoMono-Light", size: 24)).foregroundStyle(KoiTheme.onBase).lineLimit(2...4).focused($titleFocused)
                    if let parsed = model.parsedTitleDate {
                        Button { model.ignoreParsedDate() } label: { GlassChip(title: parsedDateLabel(parsed), symbol: "calendar", isOn: true) }.buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 13) {
                        Text("WHERE IT BELONGS").font(KoiTheme.section).tracking(2).foregroundStyle(KoiTheme.onBase.opacity(0.76))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(TodoSection.allCases) { section in
                                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { model.chooseTaskQuadrant(section) } } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(section.title).font(KoiTheme.body)
                                        Text("\(section.hint) · \(model.count(in: section)) here").font(KoiTheme.caption).opacity(0.72)
                                    }.foregroundStyle(KoiTheme.onBase)
                                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading).padding(13)
                                        .background(model.taskDraft.hasChosenQuadrant && model.taskDraft.quadrant == section ? AnyShapeStyle(.ultraThinMaterial.opacity(0.65)) : AnyShapeStyle(.ultraThinMaterial.opacity(0.28)), in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(KoiTheme.onBase.opacity(model.taskDraft.hasChosenQuadrant && model.taskDraft.quadrant == section ? 0.68 : 0.28)))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHEN").font(KoiTheme.section).tracking(2).foregroundStyle(KoiTheme.onBase.opacity(0.76))
                        HStack(spacing: 8) {
                            Button { model.chooseTaskDate(nil) } label: { GlassChip(title: "No date", isOn: model.taskDraft.dueAt == nil) }.buttonStyle(.plain)
                            Button { model.chooseTaskDate(model.taskDraft.dueAt ?? .now) } label: { GlassChip(title: "Pick a day", symbol: "calendar", isOn: model.taskDraft.dueAt != nil) }.buttonStyle(.plain)
                        }
                        if model.taskDraft.dueAt != nil {
                    DatePicker(model.taskDraft.hasTime ? "Day and time" : "Day", selection: Binding(get: { model.taskDraft.dueAt ?? .now }, set: { model.chooseTaskDate($0) }), displayedComponents: model.taskDraft.hasTime ? [.date, .hourAndMinute] : [.date])
                        .font(KoiTheme.body).tint(KoiTheme.onBase).foregroundStyle(KoiTheme.onBase)
                    Button(model.taskDraft.hasTime ? "Remove time" : "Add a time") { model.setTaskHasTime(!model.taskDraft.hasTime) }
                        .buttonStyle(QuietTextButtonStyle())
                        }
                    }
                    HStack { Text("+ Note").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase); Spacer() }
                    TextField("", text: Binding(get: { model.taskDraft.notes }, set: { model.taskDraft.notes = $0 }), prompt: Text("A note, if it helps").foregroundColor(KoiTheme.onBase.opacity(0.68)), axis: .vertical)
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase).lineLimit(2...5)
                    KoiPrimaryButton(title: buttonTitle) {
                        let isNew = model.editingTaskID == nil
                        if model.saveTask() {
                            if isNew {
                                analyticsProvider.signal("Task.placed", parameters: [
                                    "section": model.taskDraft.quadrant.title,
                                    "has_date": model.taskDraft.dueAt == nil ? "false" : "true",
                                    "has_time": model.taskDraft.hasTime ? "true" : "false"
                                ])
                            }
                            KoiHaptics.success()
                        }
                        if !embedded && !model.showingNewTask { dismiss() }
                    }
                        .disabled(!model.canSaveTask).opacity(model.canSaveTask ? 1 : 0.52)
        }.padding(21)
        }

    private var buttonTitle: String {
        let date = model.taskDraft.dueAt.map { " · \(taskDueLabel($0))" } ?? ""
        if model.editingTaskID != nil { return "Save changes\(date)" }
        return "Add to \(model.taskDraft.quadrant.title)\(date)"
    }

    private func parsedDateLabel(_ parsed: ParsedDate) -> String {
        taskDueLabel(parsed.date)
    }

    private func taskDueLabel(_ date: Date) -> String {
        let day: String
        if Calendar.current.isDateInToday(date) { day = "today" }
        else if Calendar.current.isDateInTomorrow(date) { day = "tomorrow" }
        else { day = date.formatted(.dateTime.weekday(.abbreviated)) }
        return !model.taskDraft.hasTime ? day : "\(day) at \(date.formatted(date: .omitted, time: .shortened))"
    }
}

private struct NewHabitSheet: View {
    @Bindable var model: TodoViewModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    private let days: [(String, Int)] = [("M", 2), ("T", 3), ("W", 4), ("T", 5), ("F", 6), ("S", 7), ("S", 1)]

    var body: some View {
        Group {
            if embedded {
                formContent
            } else {
                NavigationStack {
                    ScrollView { formContent }
                        .background(KoiBackground().ignoresSafeArea())
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Cancel") { model.cancelNewHabit(); dismiss() }
                                    .foregroundStyle(KoiTheme.onBase)
                            }
                        }
                }
            }
        }
        .presentationDetents(embedded ? [] : [.large])
        .preferredColorScheme(embedded ? nil : .dark)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { titleFocused = true } }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 21) {
                    TextField("", text: Binding(get: { model.habitDraft.title }, set: { model.habitDraft.title = $0 }), prompt: Text("What would you like to make a habit?").foregroundColor(KoiTheme.onBase.opacity(0.68)), axis: .vertical)
                        .font(.custom("RobotoMono-Light", size: 24)).foregroundStyle(KoiTheme.onBase).lineLimit(2...4).focused($titleFocused)
                    TextField("", text: Binding(get: { model.habitDraft.note }, set: { model.habitDraft.note = $0 }), prompt: Text("+ Note").foregroundColor(KoiTheme.onBase.opacity(0.68)))
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase)
                    VStack(alignment: .leading, spacing: 13) {
                        Text("HOW OFTEN").font(KoiTheme.section).tracking(2).foregroundStyle(KoiTheme.onBase.opacity(0.76))
                        HStack(spacing: 6) { scheduleChip("Daily", "daily"); scheduleChip("Weekly", "weekly"); scheduleChip("Some days", "someDays"); scheduleChip("Monthly", "monthly") }
                        if model.habitDraft.schedule == "someDays" {
                            HStack(spacing: 8) { ForEach(days, id: \.1) { title, day in Button { if model.habitDraft.weekdays.contains(day) { model.habitDraft.weekdays.remove(day) } else { model.habitDraft.weekdays.insert(day) } } label: { GlassChip(title: title, isOn: model.habitDraft.weekdays.contains(day)) }.buttonStyle(.plain) } }
                        }
                    }
                    VStack(alignment: .leading, spacing: 13) {
                        Text("WHEN").font(KoiTheme.section).tracking(2).foregroundStyle(KoiTheme.onBase.opacity(0.76))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            timeChip("Any time", nil)
                            timeChip("Morning · 8", 8)
                            timeChip("Midday · 12", 12)
                            timeChip("Evening · 7", 19)
                            exactTimeChip
                        }
                        if model.habitDraft.usesExactReminderTime {
                            DatePicker("Reminder time", selection: Binding(get: { reminderDate }, set: { value in
                                model.setReminderTime(hour: Calendar.current.component(.hour, from: value), minute: Calendar.current.component(.minute, from: value), exact: true)
                            }), displayedComponents: .hourAndMinute)
                            .font(KoiTheme.body).tint(KoiTheme.onBase).foregroundStyle(KoiTheme.onBase)
                        }
                    }
                    TextField("", text: Binding(get: { model.habitDraft.minimumVersion }, set: { model.habitDraft.minimumVersion = $0 }), prompt: Text("Two-minute version (optional)").foregroundColor(KoiTheme.onBase.opacity(0.68)))
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase)
                    TextField("", text: Binding(get: { model.habitDraft.stackingCue }, set: { model.habitDraft.stackingCue = $0 }), prompt: Text("After I…").foregroundColor(KoiTheme.onBase.opacity(0.68)))
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase)
                    TextField("", text: Binding(get: { model.habitDraft.identity }, set: { model.habitDraft.identity = $0 }), prompt: Text("Who you're becoming (optional)").foregroundColor(KoiTheme.onBase.opacity(0.68)))
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase)
                    KoiPrimaryButton(title: habitButtonTitle) {
                        if model.saveHabit() { KoiHaptics.success() }
                        if !embedded && !model.showingNewHabit { dismiss() }
                    }
                        .disabled(!model.canSaveHabit).opacity(model.canSaveHabit ? 1 : 0.52)
        }.padding(21)
        }

    private var habitButtonTitle: String {
        let schedule = model.habitDraft.schedule == "someDays" ? "some days" : model.habitDraft.schedule
        let time = model.habitDraft.reminderHour.map { " · \(Calendar.current.date(from: DateComponents(hour: $0, minute: 0))?.formatted(date: .omitted, time: .shortened) ?? "")" } ?? ""
        return "\(model.editingHabitID == nil ? "Start" : "Save") · \(schedule)\(time)"
    }
    private func scheduleChip(_ title: String, _ value: String) -> some View { Button { model.habitDraft.schedule = value } label: { GlassChip(title: title, isOn: model.habitDraft.schedule == value) }.buttonStyle(.plain) }
    private var reminderDate: Date {
        Calendar.current.date(from: DateComponents(hour: model.habitDraft.reminderHour ?? 8, minute: model.habitDraft.reminderMinute)) ?? .now
    }
    private var exactTimeChip: some View {
        Button { model.setReminderTime(hour: model.habitDraft.reminderHour ?? 8, minute: model.habitDraft.reminderMinute, exact: true) } label: {
            GlassChip(title: "Exact time", isOn: model.habitDraft.usesExactReminderTime)
        }.buttonStyle(.plain)
    }
    private func timeChip(_ title: String, _ hour: Int?) -> some View { Button { model.setReminderTime(hour: hour, minute: 0) } label: { GlassChip(title: title, isOn: model.habitDraft.reminderHour == hour && !model.habitDraft.usesExactReminderTime) }.buttonStyle(.plain) }
}

private struct TodoSwipeRow<Content: View>: View {
    let isDone: Bool
    let onComplete: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0
    @State private var horizontal: Bool?
    @State private var revealed = false

    private let completeAt: CGFloat = 80
    private let deleteWidth: CGFloat = 76

    var body: some View {
        ZStack {
            HStack {
                Image(systemName: isDone ? "arrow.uturn.backward" : "checkmark")
                    .font(.system(size: 15, weight: .light))
                    .opacity(offset > 20 ? min(1, offset / completeAt) : 0)
                Spacer()
                Button {
                    KoiHaptics.tap()
                    withAnimation(.snappy) { offset = 0; revealed = false }
                    onDelete()
                } label: {
                    Text("Delete").font(KoiTheme.caption).frame(width: deleteWidth, height: 44)
                }
                .buttonStyle(.plain)
                .opacity(offset < -20 ? 1 : 0)
            }
            .foregroundStyle(KoiTheme.onBase)
            content.offset(x: offset)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { drag in
                    if horizontal == nil {
                        horizontal = abs(drag.translation.width) > abs(drag.translation.height) * 1.5
                    }
                    guard horizontal == true else { return }
                    let base: CGFloat = revealed ? -deleteWidth : 0
                    let next = base + drag.translation.width
                    if offset < completeAt && next >= completeAt { KoiHaptics.tick() }
                    offset = min(next, completeAt * 1.3)
                }
                .onEnded { _ in
                    defer { horizontal = nil }
                    guard horizontal == true else { return }
                    if offset >= completeAt {
                        if isDone { KoiHaptics.tap() } else { KoiHaptics.check() }
                        onComplete()
                        withAnimation(.snappy) { offset = 0; revealed = false }
                    } else if offset < -deleteWidth / 2 {
                        withAnimation(.snappy) { offset = -deleteWidth; revealed = true }
                    } else {
                        withAnimation(.snappy) { offset = 0; revealed = false }
                    }
                }
        )
        .accessibilityAction(named: isDone ? "Mark incomplete" : "Mark complete", onComplete)
        .accessibilityAction(named: "Delete", onDelete)
        .animation(.snappy, value: isDone)
    }
}

private struct CheckCircle: View {
    let isOn: Bool
    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 21, weight: .light)).foregroundStyle(KoiTheme.onBase.opacity(isOn ? 0.96 : 0.68))
            .frame(width: 32, height: 32).contentTransition(.symbolEffect(.replace))
    }
}

private struct QuietTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(configuration.isPressed ? 0.55 : 0.9)).padding(.vertical, 5)
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
