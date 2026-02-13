package plan

import (
	"bufio"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
)

type Task struct {
	ID          int
	Title       string
	Description string
	FilePaths   []string
	DependsOn   []int
}

var taskHeaderRe = regexp.MustCompile(`^#{2,3} Task (\d+): (.+)`)
var fileLineRe = regexp.MustCompile("^- (?:Create|Modify|Test): `([^`]+)`")
var depsRe = regexp.MustCompile(`Task (\d+)`)

func ParsePlan(r io.Reader) ([]Task, error) {
	scanner := bufio.NewScanner(r)
	var tasks []Task
	var current *Task
	collectingFiles := false
	var descLines []string

	flush := func() {
		if current != nil {
			current.Description = strings.TrimSpace(strings.Join(descLines, "\n"))
			tasks = append(tasks, *current)
		}
	}

	for scanner.Scan() {
		line := scanner.Text()

		if m := taskHeaderRe.FindStringSubmatch(line); m != nil {
			flush()
			id, _ := strconv.Atoi(m[1])
			current = &Task{ID: id, Title: m[2]}
			collectingFiles = false
			descLines = []string{line}
			continue
		}

		if current == nil {
			continue
		}

		descLines = append(descLines, line)

		// Files header
		if matched, _ := regexp.MatchString(`(?i)^\*?\*?Files:?\*?\*?`, line); matched {
			collectingFiles = true
			continue
		}

		// Collect file paths
		if collectingFiles {
			if m := fileLineRe.FindStringSubmatch(line); m != nil {
				path := m[1]
				// Strip line range suffix like :10-20
				if idx := strings.LastIndex(path, ":"); idx > 0 {
					if _, err := strconv.Atoi(string(path[idx+1])); err == nil {
						path = path[:idx]
					}
				}
				current.FilePaths = append(current.FilePaths, path)
				continue
			}
			if line != "" {
				collectingFiles = false
			}
		}

		// Dependencies
		if matched, _ := regexp.MatchString(`(?i)^\*?\*?Dependencies:?\*?\*?`, line); matched {
			if !strings.Contains(strings.ToLower(line), "none") {
				for _, m := range depsRe.FindAllStringSubmatch(line, -1) {
					id, _ := strconv.Atoi(m[1])
					current.DependsOn = append(current.DependsOn, id)
				}
			}
		}
	}
	flush()
	return tasks, scanner.Err()
}

func ComputeWaves(tasks []Task) map[int]int {
	waves := make(map[int]int)
	var depth func(id int) int
	depth = func(id int) int {
		if w, ok := waves[id]; ok {
			return w
		}
		var t *Task
		for i := range tasks {
			if tasks[i].ID == id {
				t = &tasks[i]
				break
			}
		}
		if t == nil || len(t.DependsOn) == 0 {
			waves[id] = 0
			return 0
		}
		maxDep := 0
		for _, dep := range t.DependsOn {
			if d := depth(dep); d > maxDep {
				maxDep = d
			}
		}
		waves[id] = maxDep + 1
		return maxDep + 1
	}
	for _, t := range tasks {
		depth(t.ID)
	}
	return waves
}

func WaveCount(waves map[int]int) int {
	max := 0
	for _, w := range waves {
		if w > max {
			max = w
		}
	}
	return max + 1
}

func TasksInWave(tasks []Task, waves map[int]int, wave int) []Task {
	var result []Task
	for _, t := range tasks {
		if waves[t.ID] == wave {
			result = append(result, t)
		}
	}
	return result
}

func Validate(tasks []Task) error {
	ids := make(map[int]bool)
	for _, t := range tasks {
		ids[t.ID] = true
	}
	for _, t := range tasks {
		for _, dep := range t.DependsOn {
			if !ids[dep] {
				return fmt.Errorf("task %d references non-existent dependency task %d", t.ID, dep)
			}
		}
	}
	// Cycle detection
	for _, t := range tasks {
		if hasCycle(t.ID, nil, tasks) {
			return fmt.Errorf("dependency cycle detected involving task %d", t.ID)
		}
	}
	return nil
}

func hasCycle(id int, visited []int, tasks []Task) bool {
	for _, v := range visited {
		if v == id {
			return true
		}
	}
	for _, t := range tasks {
		if t.ID == id {
			for _, dep := range t.DependsOn {
				if hasCycle(dep, append(visited, id), tasks) {
					return true
				}
			}
			break
		}
	}
	return false
}

func ExtractTaskSpec(tasks []Task, id int) string {
	for _, t := range tasks {
		if t.ID == id {
			return t.Description
		}
	}
	return ""
}

func DetectFileOverlaps(tasks []Task) []Task {
	for i := range tasks {
		for j := i + 1; j < len(tasks); j++ {
			for _, fi := range tasks[i].FilePaths {
				for _, fj := range tasks[j].FilePaths {
					if fi == fj {
						found := false
						for _, d := range tasks[j].DependsOn {
							if d == tasks[i].ID {
								found = true
								break
							}
						}
						if !found {
							tasks[j].DependsOn = append(tasks[j].DependsOn, tasks[i].ID)
						}
					}
				}
			}
		}
	}
	return tasks
}
