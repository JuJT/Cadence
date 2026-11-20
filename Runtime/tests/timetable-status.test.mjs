import test from 'node:test';
import assert from 'node:assert/strict';
import {mapLesson} from '../src/mapping.js';

test('preserves PRONOTE timetable status independently of cancellation', () => {
  const lesson = {id: 'm', startDate: new Date(2026, 10, 24, 9), endDate: new Date(2026, 10, 24, 10)};
  assert.equal(mapLesson({...lesson, status: '<b>Professeur absent</b>'}).status_label, 'Professeur absent');
  assert.equal(mapLesson({...lesson, canceled: true}).status_label, null);
});
