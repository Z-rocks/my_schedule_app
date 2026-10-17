package com.zys.myschedule.widget

import org.json.JSONArray
import org.json.JSONObject

/**
 * 小组件快照数据（对应 Dart `widget_snapshot_service.dart` 的 schema）。
 *
 * **契约**：字段含义、缺省值以 Dart 侧 docs/widget_task_breakdown.md P1.2 为准；
 * [WidgetSnapshotParser] 对任何字段缺失 / 类型异常都返回安全缺省值，
 * 绝不在小组件进程里抛异常。
 */
data class WidgetSnapshot(
    val version: Int,
    val updatedLabel: String,
    val hasSemester: Boolean,
    val semesterName: String,
    val week: Int,
    val today: Int,
    val todayLabel: String,
    /** 本学期一门可见课程都没有（同步失败 / 新装 App）。 */
    val scheduleEmpty: Boolean,
    /** 本周是否有课（单双周课的淡周为 false，空态文案不同）。 */
    val weekHasClass: Boolean,
    val sectionTimes: Map<Int, String>,
    val schedule: ScheduleSnapshot,
    val homework: HomeworkSnapshot,
    val exam: ExamSnapshot,
)

data class ScheduleSnapshot(
    val week: Int,
    val semesterName: String,
    val today: Int,
    val maxSession: Int,
    /** 课程索引表：[WidgetCourse] 顺序即索引。 */
    val courseTable: List<WidgetCourse>,
    /** 7 行 × 12 列，值为课程索引，-1 表示空格。 */
    val cells: List<List<Int>>,
    /** 当天的课程序列（跨节已合并）。 */
    val todaySessions: List<TodaySession>,
)

data class WidgetCourse(
    val name: String,
    val room: String,
    /** ARGB 整数（Dart 侧已算好，含用户自定义色 / 哈希兜底色）。 */
    val color: Int,
)

data class TodaySession(
    val courseIdx: Int,
    val session: Int,
    val length: Int,
    /** 例："3-4节 10:25-11:10"（插件没给作息时只有 "3-4节"）。 */
    val sectionText: String,
)

data class HomeworkSnapshot(
    val pendingCount: Int,
    val overdueCount: Int,
    val items: List<HomeworkItem>,
)

data class HomeworkItem(
    val title: String,
    val course: String,
    val dueText: String,
    val daysLeftText: String,
    val overdue: Boolean,
)

data class ExamSnapshot(
    val upcomingCount: Int,
    val items: List<ExamItem>,
)

data class ExamItem(
    val name: String,
    val location: String,
    val startText: String,
    val daysLeftText: String,
)

/**
 * 快照 JSON 解析器（org.json，零三方依赖）。
 *
 * 解析失败（坏 JSON / 结构不对）返回 `null`；字段级异常一律降级为缺省值，
 * 保证"半份好数据也能渲染出一半内容"而不是整张卡空白。
 */
object WidgetSnapshotParser {

    private const val EMPTY_COURSE = "–"

    fun parse(json: String): WidgetSnapshot? {
        if (json.isBlank()) return null
        return try {
            val root = JSONObject(json)
            val version = root.optInt("version", -1)
            // 版本不匹配（将来 schema 升级）→ 视为不可用，卡片显示
            // "请打开 App 更新"，不猜旧字段的含义。
            if (version != com.zys.myschedule.widget.WidgetSnapshotContract.VERSION) {
                return null
            }
            WidgetSnapshot(
                version = version,
                updatedLabel = root.optString("updatedLabel", ""),
                hasSemester = root.optBoolean("hasSemester", false),
                semesterName = root.optString("semesterName", ""),
                week = root.optInt("week", 1),
                today = root.optInt("today", 1),
                todayLabel = root.optString("todayLabel", ""),
                scheduleEmpty = root.optBoolean("scheduleEmpty", true),
                weekHasClass = root.optBoolean("weekHasClass", false),
                sectionTimes = parseSectionTimes(root.optJSONObject("sectionTimes")),
                schedule = parseSchedule(root.optJSONObject("schedule")),
                homework = parseHomework(root.optJSONObject("homework")),
                exam = parseExam(root.optJSONObject("exam")),
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun parseSectionTimes(obj: JSONObject?): Map<Int, String> {
        if (obj == null) return emptyMap()
        val result = HashMap<Int, String>()
        for (key in obj.keys()) {
            val session = key.toIntOrNull() ?: continue
            val text = obj.optString(key, "")
            if (text.isNotEmpty()) result[session] = text
        }
        return result
    }

    private fun parseSchedule(obj: JSONObject?): ScheduleSnapshot {
        if (obj == null) return ScheduleSnapshot(
            week = 1, semesterName = "", today = 1, maxSession = 0,
            courseTable = emptyList(), cells = List(7) { List(12) { -1 } },
            todaySessions = emptyList(),
        )
        val table = ArrayList<WidgetCourse>()
        val tableJson = obj.optJSONArray("courseTable")
        if (tableJson != null) {
            for (i in 0 until tableJson.length()) {
                val c = tableJson.optJSONObject(i) ?: continue
                table.add(
                    WidgetCourse(
                        name = c.optString("name", EMPTY_COURSE),
                        room = c.optString("room", ""),
                        color = c.optInt("color", 0xFFB0BEC5.toInt()),
                    )
                )
            }
        }
        val cells = ArrayList<List<Int>>()
        val cellsJson = obj.optJSONArray("cells")
        if (cellsJson != null) {
            for (i in 0 until cellsJson.length()) {
                val row = ArrayList<Int>()
                val rowJson = cellsJson.optJSONArray(i)
                if (rowJson != null) {
                    for (j in 0 until rowJson.length()) row.add(rowJson.optInt(j, -1))
                }
                // 不足 12 列补 -1，渲染循环按 12 列走，免判空。
                while (row.size < 12) row.add(-1)
                cells.add(row)
            }
        }
        while (cells.size < 7) cells.add(List(12) { -1 })

        val sessions = ArrayList<TodaySession>()
        val sessionsJson = obj.optJSONArray("todaySessions")
        if (sessionsJson != null) {
            for (i in 0 until sessionsJson.length()) {
                val s = sessionsJson.optJSONObject(i) ?: continue
                sessions.add(
                    TodaySession(
                        courseIdx = s.optInt("courseIdx", -1),
                        session = s.optInt("session", 1),
                        length = s.optInt("length", 1),
                        sectionText = s.optString("sectionText", ""),
                    )
                )
            }
        }
        return ScheduleSnapshot(
            week = obj.optInt("week", 1),
            semesterName = obj.optString("semesterName", ""),
            today = obj.optInt("today", 1),
            maxSession = obj.optInt("maxSession", 0),
            courseTable = table,
            cells = cells,
            todaySessions = sessions,
        )
    }

    private fun parseHomework(obj: JSONObject?): HomeworkSnapshot {
        if (obj == null) return HomeworkSnapshot(0, 0, emptyList())
        val items = ArrayList<HomeworkItem>()
        val itemsJson = obj.optJSONArray("items")
        if (itemsJson != null) {
            for (i in 0 until itemsJson.length()) {
                val it = itemsJson.optJSONObject(i) ?: continue
                items.add(
                    HomeworkItem(
                        title = it.optString("title", ""),
                        course = it.optString("course", ""),
                        dueText = it.optString("dueText", ""),
                        daysLeftText = it.optString("daysLeftText", ""),
                        overdue = it.optBoolean("overdue", false),
                    )
                )
            }
        }
        return HomeworkSnapshot(
            pendingCount = obj.optInt("pendingCount", 0),
            overdueCount = obj.optInt("overdueCount", 0),
            items = items,
        )
    }

    private fun parseExam(obj: JSONObject?): ExamSnapshot {
        if (obj == null) return ExamSnapshot(0, emptyList())
        val items = ArrayList<ExamItem>()
        val itemsJson = obj.optJSONArray("items")
        if (itemsJson != null) {
            for (i in 0 until itemsJson.length()) {
                val it = itemsJson.optJSONObject(i) ?: continue
                items.add(
                    ExamItem(
                        name = it.optString("name", ""),
                        location = it.optString("location", ""),
                        startText = it.optString("startText", ""),
                        daysLeftText = it.optString("daysLeftText", ""),
                    )
                )
            }
        }
        return ExamSnapshot(upcomingCount = obj.optInt("upcomingCount", 0), items = items)
    }

    /** JSONArray 安全取值辅助（解析里只用 optXxx，这个只是预留给未来的遍历）。 */
    internal fun JSONArray.forEachObject(action: (JSONObject) -> Unit) {
        for (i in 0 until length()) optJSONObject(i)?.let(action)
    }
}
