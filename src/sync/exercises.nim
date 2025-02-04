import std/[algorithm, json, options, os, sequtils, sets, strformat, strutils,
            tables]
import pkg/parsetoml
import ".."/cli
import "."/[probspecs, tracks]

type
  ExerciseTestCase* = ref object
    uuid*: string
    description*: string
    json*: JsonNode
    reimplements*: Option[ExerciseTestCase]

  ExerciseTests* = object
    included*: HashSet[string]
    excluded*: HashSet[string]
    missing*: HashSet[string]

  ExerciseStatus* = enum
    exOutOfSync, exInSync, exNoCanonicalData

  Exercise* = object
    slug*: string
    tests*: ExerciseTests
    testCases*: seq[ExerciseTestCase]

func initExerciseTests*(included, excluded, missing: HashSet[string]): ExerciseTests =
  ExerciseTests(
    included: included,
    excluded: excluded,
    missing: missing,
  )

proc initExerciseTests(trackExercise: TrackExercise, probSpecsExercise: ProbSpecsExercise): ExerciseTests =
  for testCase in probSpecsExercise.testCases:
    if trackExercise.tests.included.contains(testCase.uuid):
      result.included.incl(testCase.uuid)
    elif trackExercise.tests.excluded.contains(testCase.uuid):
      result.excluded.incl(testCase.uuid)
    else:
      result.missing.incl(testCase.uuid)

proc newExerciseTestCase(testCase: ProbSpecsTestCase): ExerciseTestCase =
  ExerciseTestCase(
    uuid: testCase.uuid,
    description: testCase.description,
    json: testCase.json,
  )

proc initExerciseTestCases(testCases: seq[ProbSpecsTestCase]): seq[ExerciseTestCase] =
  for testCase in testCases:
    result.add(newExerciseTestCase(testCase))

  let reimplementations = testCases.filterIt(it.isReimplementation).mapIt((it.uuid, it.reimplements)).toTable()
  let testCasesByUuids = result.newTableFrom(proc (testCase: ExerciseTestCase): string = testCase.uuid)

  for testCase in result:
    if testCase.uuid in reimplementations:
      testCase.reimplements = some(testCasesByUuids[reimplementations[testCase.uuid]])

proc initExercise(trackExercise: TrackExercise, probSpecsExercise: ProbSpecsExercise): Exercise =
  Exercise(
    slug: trackExercise.slug,
    tests: initExerciseTests(trackExercise, probSpecsExercise),
    testCases: initExerciseTestCases(probSpecsExercise.testCases),
  )

proc findExercises*(conf: Conf): seq[Exercise] =
  let probSpecsExercises = findProbSpecsExercises(conf).mapIt((it.slug, it)).toTable

  for trackExercise in findTrackExercises(conf).sortedByIt(it.slug):
    result.add(initExercise(trackExercise, probSpecsExercises.getOrDefault(trackExercise.slug)))

func status*(exercise: Exercise): ExerciseStatus =
  if exercise.testCases.len == 0:
    exNoCanonicalData
  elif exercise.tests.missing.len > 0:
    exOutOfSync
  else:
    exInSync

func hasCanonicalData*(exercise: Exercise): bool =
  exercise.testCases.len > 0

func testsFile(exercise: Exercise, trackDir: string): string =
  trackDir / "exercises" / "practice" / exercise.slug / ".meta" / "tests.toml"

func prettyTomlString(s: string): string =
  ## Returns `s` as a TOML string. This tries to handle multi-line strings,
  ## which `parsetoml.toTomlString` doesn't handle properly.
  if s.contains("\n"):
    &"\"\"\"\n{s}\"\"\""
  else:
    &"\"{s}\""

proc prettyTomlString(a: openArray[TomlValueRef]): string =
  ## Returns the array `a` as a prettified TOML string.
  if a.len > 0:
    result = "[\n"
    for item in a:
      result.add &"  {item.toTomlString()},\n" # Keep the final trailing comma.
    result.add "]"
  else:
    result = "[]"

proc toToml(exercise: Exercise, testsPath: string): string =
  ## Returns the new contents of a `tests.toml` file that corresponds to an
  ## `exercise`. This proc reads the previous contents at `testsPath` and
  ## preserves every property apart from `description` and `include = true`.
  result = """
# This is an auto-generated file. Regular comments will be removed when this
# file is regenerated. Regenerating will not touch any manually added keys,
# so comments can be added in a "comment" key.

"""

  for testCase in exercise.testCases:
    if testCase.uuid notin exercise.tests.missing:
      result.add &"[{testCase.uuid}]\n"
      # Always use the latest `description` value
      result.add &"description = \"{testCase.description}\"\n"

      # Omit `include = true`
      if testCase.uuid notin exercise.tests.included:
        result.add "include = false\n"

      if fileExists(testsPath):
        let currContents = parsetoml.parseFile(testsPath)
        if currContents.hasKey(testCase.uuid):
          # Preserve custom properties
          for k, v in currContents[testCase.uuid].getTable():
            if k notin ["description", "include"].toHashSet():
              let vTomlString =
                if v.kind == String:
                  prettyTomlString(v.stringVal)
                elif v.kind == Array:
                  prettyTomlString(v.arrayVal)
                else:
                  toTomlString(v)
              result.add &"{k} = {vTomlString}\n"

      result.add "\n"

  result.setLen(result.len - 1)

proc writeTestsToml*(exercise: Exercise, trackDir: string) =
  let testsPath = testsFile(exercise, trackDir)
  createDir(testsPath.parentDir())

  let contents = toToml(exercise, testsPath)
  writeFile(testsPath, contents)
