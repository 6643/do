declare module "node:assert/strict" {
    interface Assert {
        equal(actual: unknown, expected: unknown, message?: string): void;
    }

    const assert: Assert;
    export default assert;
}

declare module "node:test" {
    type TestBody = () => void | Promise<void>;

    interface Test {
        (name: string, body: TestBody): void;
    }

    const test: Test;
    export default test;
}
